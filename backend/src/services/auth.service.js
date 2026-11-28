const bcrypt = require('bcryptjs');
const config = require('../config');
const users = require('../repositories/user.repository');
const ledger = require('../repositories/ledger.repository');
const session = require('./session.service');
const { sendResetLink, sendVerificationLink, mailEnabled } = require('./mail.service');
const { defaultWallets, defaultCategories, defaultPeople } = require('../domain/defaults');
const validate = require('../validators/auth.validator');
const { randomToken, sha256 } = require('../utils/crypto');
const { badRequest, conflict, forbidden, unauthorized, serviceUnavailable, tooMany } = require('../utils/errors');

const WRONG_CREDENTIALS = 'Email hoặc mật khẩu không đúng.';

function assertMailConfigured() {
  if (config.isProduction && (!mailEnabled() || !config.publicUrl || !config.publicUrl.startsWith('https://'))) {
    throw serviceUnavailable('Máy chủ chưa cấu hình email và PUBLIC_URL để gửi liên kết xác thực.');
  }
}

function actionLink(path, token) {
  return `financeapp://auth/${path}?token=${encodeURIComponent(token)}`;
}

function webActionLink(path, token) {
  const base = config.publicUrl || `http://localhost:${config.port}`;
  return `${base}/api/auth/${path}?token=${encodeURIComponent(token)}`;
}

function emailActionLink(path, token) {
  const base = config.publicUrl || `http://localhost:${config.port}`;
  return `${base}/api/auth/open-app/${path}?token=${encodeURIComponent(token)}`;
}

async function sendActionLink(user, token, path, send) {
  assertMailConfigured();
  const appLink = actionLink(path, token);
  const webLink = webActionLink(path, token);
  const link = emailActionLink(path, token);
  const sent = await send(user.email, user.name, appLink, webLink, link);
  if (!sent && config.isProduction) {
    throw serviceUnavailable('Không gửi được email. Vui lòng kiểm tra cấu hình SMTP hoặc Brevo.');
  }
  return {
    mailEnabled: sent,
    ...(!sent ? { devLink: link, devAppLink: appLink, devWebLink: webLink } : {}),
  };
}

async function register(body) {
  const name = validate.fullName(body.name);
  const email = validate.newEmail(body.email);
  const password = validate.newPassword(body.password, email);
  const existing = await users.findByEmail(email);
  if (existing?.emailVerified) throw conflict('Email đã được đăng ký.', 'EMAIL_EXISTS');
  assertMailConfigured();
  const token = randomToken(32);
  const tokenFields = {
    emailVerifyTokenHash: sha256(token),
    emailVerifyTokenExpires: new Date(Date.now() + config.emailVerifyMinutes * 60000),
  };
  let user = existing;
  if (user) {
    user.name = name;
    user.passwordHash = await bcrypt.hash(password, 10);
    Object.assign(user, tokenFields);
    await users.save(user);
  } else {
    user = await users.create({ name, email, passwordHash: await bcrypt.hash(password, 10), ...tokenFields });
    if (body.seedDefaults !== false) {
      await ledger.seed(user._id, { wallets: defaultWallets, categories: defaultCategories, people: defaultPeople });
    }
  }
  const delivery = await sendActionLink(user, token, 'verify-email', sendVerificationLink);
  return { message: 'Hãy mở email và xác minh địa chỉ để hoàn tất đăng ký.', ...delivery };
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
  if (Buffer.byteLength(password, 'utf8') > 72) throw unauthorized(WRONG_CREDENTIALS);
  const user = await users.findByEmail(email);
  if (user?.lockUntil > new Date()) {
    const remainingMs = user.lockUntil - Date.now();
    const remaining =
      remainingMs < 60000 ? `${Math.ceil(remainingMs / 1000)} giây` : `${Math.ceil(remainingMs / 60000)} phút`;
    throw tooMany(`Tài khoản tạm khóa do nhập sai mật khẩu nhiều lần. Thử lại sau ${remaining}.`, 'ACCOUNT_LOCKED');
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
  if (!user.emailVerified) {
    throw forbidden('Email chưa được xác minh. Hãy mở liên kết trong email trước khi đăng nhập.', 'EMAIL_NOT_VERIFIED');
  }
  return session.issue(user);
}

async function verifyEmail(token) {
  const value = validate.actionToken(token);
  const user = await users.verifyEmail(sha256(value), new Date());
  if (!user) throw badRequest('Liên kết xác minh không hợp lệ hoặc đã hết hạn.', 'VERIFY_LINK_INVALID');
  return { message: 'Email đã được xác minh. Bạn có thể quay lại ứng dụng để đăng nhập.', user: user.toJSON() };
}

async function resendVerification(body) {
  const email = validate.existingEmail(body.email);
  assertMailConfigured();
  const result = { message: 'Nếu email chưa được xác minh, một liên kết xác minh sẽ được gửi.' };
  const user = await users.findByEmail(email);
  if (!user || user.emailVerified) return result;

  const token = randomToken(32);
  user.emailVerifyTokenHash = sha256(token);
  user.emailVerifyTokenExpires = new Date(Date.now() + config.emailVerifyMinutes * 60000);
  await users.save(user);
  const delivery = await sendActionLink(user, token, 'verify-email', sendVerificationLink);
  return { ...result, ...(!config.isProduction && delivery.devLink ? { devLink: delivery.devLink } : {}) };
}

async function forgotPassword(body) {
  const email = validate.existingEmail(body.email);
  assertMailConfigured();
  const user = await users.findByEmail(email);
  if (!user) {
    return { registered: false, verified: false, mailEnabled: false, message: 'Email này chưa được đăng ký.' };
  }
  if (!user.emailVerified) {
    return {
      registered: true,
      verified: false,
      mailEnabled: false,
      message: 'Email đã đăng ký nhưng chưa xác minh. Hãy xác minh email trước khi đặt lại mật khẩu.',
    };
  }

  const token = randomToken(32);
  user.resetTokenHash = sha256(token);
  user.resetTokenExpires = new Date(Date.now() + config.resetTokenMinutes * 60000);
  await users.save(user);
  const delivery = await sendActionLink(user, token, 'reset-password', sendResetLink);
  return {
    registered: true,
    verified: true,
    ...delivery,
    message: delivery.mailEnabled
      ? 'Đã gửi liên kết đặt lại mật khẩu. Hãy kiểm tra hộp thư.'
      : 'Không cấu hình email; dùng liên kết kiểm tra bên dưới để đặt lại mật khẩu.',
  };
}

async function getResetContext(token) {
  const tokenHash = sha256(validate.actionToken(token));
  const now = new Date();
  const user = await users.findByResetTokenHash(tokenHash, now);
  if (!user) throw badRequest('Liên kết đặt lại mật khẩu không hợp lệ hoặc đã hết hạn.', 'RESET_LINK_INVALID');
  return { tokenHash, now, user };
}

async function validateResetToken(token) {
  await getResetContext(token);
}

async function resetPassword(body) {
  const { tokenHash, now, user } = await getResetContext(body.token);
  const password = validate.newPassword(body.newPassword, user.email, 'Mật khẩu mới');
  if (body.confirmPassword !== undefined && body.confirmPassword !== password) {
    throw badRequest('Mật khẩu nhập lại không khớp.');
  }
  const updated = await users.resetPassword(tokenHash, now, await bcrypt.hash(password, 10));
  if (!updated) throw badRequest('Liên kết đặt lại mật khẩu không hợp lệ hoặc đã hết hạn.', 'RESET_LINK_INVALID');
  await session.revokeAll(updated, { incrementVersion: false });
  return { message: 'Mật khẩu đã được cập nhật. Bạn có thể quay lại ứng dụng để đăng nhập.' };
}

async function updateProfile(user, body) {
  Object.assign(user, validate.profile(body));
  await users.save(user);
  return { user: user.toJSON() };
}

async function assertPassword(user, password, message) {
  const value = String(password || '');
  if (Buffer.byteLength(value, 'utf8') > 72 || !(await bcrypt.compare(value, user.passwordHash))) {
    throw badRequest(message, 'WRONG_PASSWORD');
  }
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
  verifyEmail,
  resendVerification,
  refresh: (body) => session.rotate(body.refreshToken),
  forgotPassword,
  validateResetToken,
  resetPassword,
  updateProfile,
  changePassword,
  logout: (user, sessionId, body = {}) =>
    session.signOut(user, {
      sessionId,
      refreshToken: body.refreshToken,
    }),
  deleteAccount,
};
