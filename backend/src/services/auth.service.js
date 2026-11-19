const bcrypt = require('bcryptjs');
const config = require('../config');
const users = require('../repositories/user.repository');
const ledger = require('../repositories/ledger.repository');
const session = require('./session.service');
const otp = require('./otp.service');
const { sendResetCode, sendVerifyCode, mailEnabled } = require('./mail.service');
const { defaultWallets, defaultCategories, defaultPeople } = require('../domain/defaults');
const validate = require('../validators/auth.validator');
const { sixDigitCode } = require('../utils/crypto');
const { badRequest, conflict, unauthorized, tooMany } = require('../utils/errors');

const WRONG_CREDENTIALS = 'Email hoặc mật khẩu không đúng.';
const MAX_RESET_ATTEMPTS = 5;

async function register(body) {
  const name = validate.fullName(body.name);
  const email = validate.newEmail(body.email);
  const password = validate.newPassword(body.password, email);
  const existing = await users.findByEmail(email);
  if (existing?.emailVerified) throw conflict('Email đã được đăng ký.', 'EMAIL_EXISTS');
  const passwordHash = await bcrypt.hash(password, 10);
  if (existing) return otp.start(existing, 'register', { pendingName: name, pendingPasswordHash: passwordHash });
  const user = await users.create({ name, email, passwordHash });
  if (body.seedDefaults !== false) {
    await ledger.seed(user._id, { wallets: defaultWallets, categories: defaultCategories, people: defaultPeople });
  }
  return otp.start(user, 'register');
}

async function recordFailedLogin(user) {
  user.failedLogins += 1;
  if (user.failedLogins >= config.maxFailedLogins) {
    user.failedLogins = 0;
    user.lockUntil = new Date(Date.now() + config.lockMinutes * 60000);
  }
  await users.save(user);
}

async function login(body) {
  const email = validate.existingEmail(body.email);
  const password = String(body.password || '');
  if (!password) throw badRequest('Vui lòng nhập mật khẩu.');
  if (password.length > 72) throw unauthorized(WRONG_CREDENTIALS);
  const user = await users.findByEmail(email);
  if (user?.lockUntil > new Date()) {
    const minutes = Math.ceil((user.lockUntil - Date.now()) / 60000);
    throw tooMany(`Tài khoản tạm khóa do nhập sai mật khẩu nhiều lần. Thử lại sau ${minutes} phút.`, 'ACCOUNT_LOCKED');
  }
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    if (user) await recordFailedLogin(user);
    throw unauthorized(WRONG_CREDENTIALS);
  }
  if (user.failedLogins || user.lockUntil) {
    user.failedLogins = 0;
    user.lockUntil = null;
    await users.save(user);
  }
  return otp.start(user, user.emailVerified ? 'login' : 'register');
}

async function verifyOtp(body) {
  const challenge = await otp.find(body.otpToken);
  await otp.verify(challenge, validate.otpCode(body.code));
  const user = await users.findById(challenge.user);
  if (!user) throw otp.expired();
  if (challenge.pendingPasswordHash) {
    user.name = challenge.pendingName;
    user.passwordHash = challenge.pendingPasswordHash;
    await session.revokeAll(user);
  }
  Object.assign(user, { emailVerified: true, verifyCodeHash: null, verifyCodeExpires: null });
  await users.save(user);
  return session.issue(user);
}

async function resendOtp(body) {
  const challenge = await otp.find(body.otpToken);
  const user = await users.findById(challenge.user);
  if (!user) throw otp.expired();
  return otp.resend(challenge, user);
}

async function verifyEmail(user, body) {
  if (user.emailVerified) return { user: user.toJSON() };
  const code = String(body.code || '').trim();
  const valid =
    user.verifyCodeHash && user.verifyCodeExpires > new Date() && (await bcrypt.compare(code, user.verifyCodeHash));
  if (!valid) throw badRequest('Mã xác thực không đúng hoặc đã hết hạn.', 'INVALID_CODE');
  Object.assign(user, { emailVerified: true, verifyCodeHash: null, verifyCodeExpires: null });
  await users.save(user);
  return { user: user.toJSON() };
}

async function resendVerification(user) {
  if (user.emailVerified) return { message: 'Email đã được xác thực.' };
  const code = sixDigitCode();
  user.verifyCodeHash = await bcrypt.hash(code, 8);
  user.verifyCodeExpires = new Date(Date.now() + 24 * 3600 * 1000);
  await users.save(user);
  const sent = await sendVerifyCode(user.email, user.name, code);
  return { message: 'Đã gửi mã xác thực.', devCode: otp.devCode(sent, code) };
}

async function forgotPassword(body) {
  const email = validate.existingEmail(body.email);
  const user = await users.findByEmail(email);
  const result = { message: 'Nếu email đã đăng ký, mã khôi phục đã được gửi.' };
  if (user) {
    const code = sixDigitCode();
    user.resetCodeHash = await bcrypt.hash(code, 8);
    user.resetCodeExpires = new Date(Date.now() + config.resetCodeMinutes * 60 * 1000);
    user.resetAttempts = 0;
    await users.save(user);
    result.devCode = otp.devCode(await sendResetCode(email, user.name, code), code);
  }
  result.mailEnabled = mailEnabled();
  return result;
}

async function resetPassword(body) {
  const email = validate.existingEmail(body.email);
  const code = validate.otpCode(body.code);
  const password = validate.newPassword(body.newPassword, email, 'Mật khẩu mới');
  const user = await users.findByEmail(email);
  const invalid = badRequest('Mã khôi phục không đúng hoặc đã hết hạn.', 'INVALID_CODE');
  if (!user?.resetCodeHash || !(user.resetCodeExpires > new Date())) throw invalid;
  if (user.resetAttempts >= MAX_RESET_ATTEMPTS)
    throw badRequest('Bạn đã nhập sai quá nhiều lần, hãy yêu cầu mã mới.', 'INVALID_CODE');
  if (!(await bcrypt.compare(code, user.resetCodeHash))) {
    user.resetAttempts += 1;
    await users.save(user);
    throw invalid;
  }
  Object.assign(user, {
    passwordHash: await bcrypt.hash(password, 10),
    resetCodeHash: null,
    resetCodeExpires: null,
    resetAttempts: 0,
    emailVerified: true,
    failedLogins: 0,
    lockUntil: null,
  });
  await session.revokeAll(user);
  await users.save(user);
  return session.issue(user);
}

async function updateProfile(user, body) {
  Object.assign(user, validate.profile(body));
  await users.save(user);
  return { user: user.toJSON() };
}

async function assertPassword(user, password, message) {
  if (!(await bcrypt.compare(String(password || ''), user.passwordHash))) throw badRequest(message, 'WRONG_PASSWORD');
}

async function changePassword(user, body) {
  await assertPassword(user, body.oldPassword, 'Mật khẩu hiện tại không đúng.');
  const password = validate.newPassword(body.newPassword, user.email, 'Mật khẩu mới');
  if (password === body.oldPassword) throw badRequest('Mật khẩu mới phải khác mật khẩu hiện tại.');
  user.passwordHash = await bcrypt.hash(password, 10);
  await session.revokeAll(user);
  await users.save(user);
  return session.issue(user);
}

async function deleteAccount(user, body) {
  await assertPassword(user, body.password, 'Mật khẩu không đúng.');
  await users.deleteWithData(user._id);
}

module.exports = {
  register,
  login,
  verifyOtp,
  resendOtp,
  refresh: (body) => session.rotate(body.refreshToken),
  verifyEmail,
  resendVerification,
  forgotPassword,
  resetPassword,
  updateProfile,
  changePassword,
  logout: (user, sessionId, body = {}) =>
    session.signOut(user, {
      sessionId,
      everywhere: body.all === true,
      refreshToken: body.refreshToken,
    }),
  deleteAccount,
};
