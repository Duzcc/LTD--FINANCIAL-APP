const router = require('express').Router();
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const config = require('../config');
const wrap = require('../middleware/async');
const { requireAuth, signToken } = require('../middleware/auth');
const { User, Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken, OtpChallenge, PaymentRequest, BankEvent } = require('../models');
const { defaultWallets, defaultCategories, defaultPeople } = require('../services/defaults');
const { badRequest, conflict, unauthorized, tooMany } = require('../services/errors');
const { sendResetCode, sendVerifyCode, sendOtpCode, mailEnabled } = require('../services/mailer');
const { CURRENCIES } = require('../services/constants');

// Ràng buộc dữ liệu tài khoản (đồng bộ với frontend: features/auth/presentation/validators.dart)
const EMAIL = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;
const NAME = /^[\p{L}][\p{L} .'-]*$/u;
const OTP = /^\d{6}$/;
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: Number(process.env.AUTH_RATE_LIMIT) || 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: { code: 'TOO_MANY_REQUESTS', message: 'Bạn thử quá nhiều lần, vui lòng đợi ít phút.' } },
});

function email(v) {
  const e = String(v || '').trim().toLowerCase();
  if (!e) throw badRequest('Vui lòng nhập email.');
  if (e.length > 254 || e.split('@')[0].length > 64) throw badRequest('Email quá dài.');
  if (!EMAIL.test(e) || e.includes('..') || /^\.|\.@/.test(e)) throw badRequest('Email không hợp lệ.');
  return e;
}
function fullName(v) {
  const n = String(v || '').trim().replace(/\s+/g, ' ');
  if (!n) throw badRequest('Vui lòng nhập họ tên.');
  if (n.length < 2) throw badRequest('Họ tên phải có ít nhất 2 ký tự.');
  if (n.length > 50) throw badRequest('Họ tên tối đa 50 ký tự.');
  if (!NAME.test(n)) throw badRequest('Họ tên chỉ gồm chữ cái và khoảng trắng.');
  return n;
}
// Mật khẩu mới: 8–72 ký tự, có cả chữ và số, không chứa khoảng trắng, không trùng email.
function password(v, field = 'Mật khẩu', mail = '') {
  const p = String(v || '');
  if (!p) throw badRequest(`Vui lòng nhập ${field.toLowerCase()}.`);
  if (p.length < 8) throw badRequest(`${field} phải có ít nhất 8 ký tự.`);
  if (p.length > 72) throw badRequest(`${field} tối đa 72 ký tự.`);
  if (/\s/.test(p)) throw badRequest(`${field} không được chứa khoảng trắng.`);
  if (!/\p{L}/u.test(p) || !/\d/.test(p)) throw badRequest(`${field} phải có cả chữ cái và chữ số.`);
  if (mail && p.toLowerCase() === mail) throw badRequest(`${field} không được trùng email.`);
  return p;
}
function otpCode(v) {
  const c = String(v || '').trim();
  if (!OTP.test(c)) throw badRequest('Mã OTP gồm đúng 6 chữ số.', 'INVALID_CODE');
  return c;
}
const newCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');
const sha = (v) => crypto.createHash('sha256').update(v).digest('hex');

// Cấp cặp token: access token (JWT, ngắn hạn) + refresh token (ngẫu nhiên, dài hạn, xoay vòng).
// Mỗi thiết bị có một mã phiên (sid) giữ nguyên qua các lần làm mới token.
async function session(user, sid = crypto.randomUUID()) {
  const refreshToken = crypto.randomBytes(48).toString('base64url');
  await RefreshToken.create({
    user: user._id,
    tokenHash: sha(refreshToken),
    version: user.tokenVersion,
    sid,
    expiresAt: new Date(Date.now() + config.refreshDays * 86400000),
  });
  return { token: signToken(user, sid), refreshToken, user: user.toJSON() };
}

async function revokeAll(user) {
  user.tokenVersion += 1;
  await RefreshToken.deleteMany({ user: user._id });
}

// Tạo mã xác thực email 6 số; trả mã ở chế độ dev khi chưa cấu hình SMTP.
async function issueVerifyCode(user) {
  const code = newCode();
  user.verifyCodeHash = await bcrypt.hash(code, 8);
  user.verifyCodeExpires = new Date(Date.now() + 24 * 3600 * 1000);
  await user.save();
  const sent = await sendVerifyCode(user.email, user.name, code);
  return !sent && !config.isProduction ? code : undefined;
}

async function seedDefaults(user) {
  await Wallet.insertMany(defaultWallets.map((w) => ({ ...w, user })));
  await Category.insertMany(defaultCategories.map((c) => ({ ...c, user })));
  await Person.insertMany(defaultPeople.map((p) => ({ ...p, user })));
}

// Tạo phiên OTP và gửi mã 6 số tới email. Chưa cấp token cho tới khi nhập đúng mã.
async function startOtp(user, purpose) {
  await OtpChallenge.deleteMany({ user: user._id, purpose }); // mỗi lúc chỉ một phiên OTP cho mỗi mục đích
  const otpToken = crypto.randomBytes(32).toString('base64url');
  const code = newCode();
  const now = Date.now();
  await OtpChallenge.create({
    user: user._id,
    purpose,
    tokenHash: sha(otpToken),
    codeHash: await bcrypt.hash(code, 8),
    expiresAt: new Date(now + config.otp.minutes * 60000),
    lastSentAt: new Date(now),
    purgeAt: new Date(now + 3600000),
  });
  const sent = await sendOtpCode(user.email, user.name, code, purpose);
  return {
    otpRequired: true,
    otpToken,
    purpose,
    email: user.email,
    expiresIn: config.otp.minutes * 60,
    resendAfter: config.otp.resendSeconds,
    mailEnabled: mailEnabled(),
    // Chế độ phát triển, chưa cấu hình SMTP: trả mã để demo/kiểm thử.
    devCode: !sent && !config.isProduction ? code : undefined,
  };
}

async function findOtp(raw) {
  const token = String(raw || '');
  const doc = token ? await OtpChallenge.findOne({ tokenHash: sha(token) }) : null;
  if (!doc) throw badRequest('Phiên xác thực đã hết hạn, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
  return doc;
}

// Đăng ký bằng email: tạo tài khoản (chưa xác thực) rồi gửi OTP. Email chưa xác thực được phép đăng ký lại.
router.post('/register', limiter, wrap(async (req, res) => {
  const name = fullName(req.body.name);
  const mail = email(req.body.email);
  const pass = password(req.body.password, 'Mật khẩu', mail);
  let user = await User.findOne({ email: mail });
  if (user?.emailVerified) throw conflict('Email đã được đăng ký.', 'EMAIL_EXISTS');
  const passwordHash = await bcrypt.hash(pass, 10);
  if (user) {
    user.name = name;
    user.passwordHash = passwordHash;
    await revokeAll(user);
    await user.save();
  } else {
    user = await User.create({ name, email: mail, passwordHash });
    if (req.body.seedDefaults !== false) await seedDefaults(user._id);
  }
  res.status(201).json(await startOtp(user, 'register'));
}));

// Đăng nhập: bước 1 kiểm tra mật khẩu và gửi OTP qua email; bước 2 là /verify-otp.
router.post('/login', limiter, wrap(async (req, res) => {
  const mail = email(req.body.email);
  const pass = String(req.body.password || '');
  if (!pass) throw badRequest('Vui lòng nhập mật khẩu.');
  if (pass.length > 72) throw unauthorized('Email hoặc mật khẩu không đúng.');
  const user = await User.findOne({ email: mail });
  if (user?.lockUntil && user.lockUntil > new Date()) {
    const min = Math.ceil((user.lockUntil - Date.now()) / 60000);
    throw tooMany(`Tài khoản tạm khóa do nhập sai mật khẩu nhiều lần. Thử lại sau ${min} phút.`, 'ACCOUNT_LOCKED');
  }
  const ok = user && (await bcrypt.compare(pass, user.passwordHash));
  if (!ok) {
    if (user) {
      user.failedLogins += 1;
      if (user.failedLogins >= config.maxFailedLogins) {
        user.failedLogins = 0;
        user.lockUntil = new Date(Date.now() + config.lockMinutes * 60000);
      }
      await user.save();
    }
    throw unauthorized('Email hoặc mật khẩu không đúng.');
  }
  user.failedLogins = 0;
  user.lockUntil = null;
  await user.save();
  res.json(await startOtp(user, user.emailVerified ? 'login' : 'register'));
}));

// Xác thực OTP → cấp phiên đăng nhập. Nhập đúng mã nghĩa là email hợp lệ.
router.post('/verify-otp', limiter, wrap(async (req, res) => {
  const doc = await findOtp(req.body.otpToken);
  const code = otpCode(req.body.code);
  if (doc.expiresAt < new Date()) {
    throw badRequest('Mã OTP đã hết hạn, hãy bấm "Gửi lại mã".', 'OTP_EXPIRED_CODE');
  }
  if (!(await bcrypt.compare(code, doc.codeHash))) {
    doc.attempts += 1;
    const left = config.otp.maxAttempts - doc.attempts;
    if (left <= 0) {
      await OtpChallenge.deleteOne({ _id: doc._id });
      throw badRequest('Bạn đã nhập sai quá nhiều lần, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
    }
    await doc.save();
    throw badRequest(`Mã OTP không đúng. Bạn còn ${left} lần thử.`, 'INVALID_CODE');
  }
  await OtpChallenge.deleteOne({ _id: doc._id });
  const user = await User.findById(doc.user);
  if (!user) throw badRequest('Phiên xác thực đã hết hạn, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
  user.emailVerified = true;
  user.verifyCodeHash = null;
  user.verifyCodeExpires = null;
  await user.save();
  res.json(await session(user));
}));

// Gửi lại OTP (chờ tối thiểu resendSeconds giữa hai lần, tối đa maxSends lần).
router.post('/resend-otp', limiter, wrap(async (req, res) => {
  const doc = await findOtp(req.body.otpToken);
  const wait = Math.ceil((doc.lastSentAt.getTime() + config.otp.resendSeconds * 1000 - Date.now()) / 1000);
  if (wait > 0) throw tooMany(`Vui lòng đợi ${wait} giây trước khi gửi lại mã.`, 'OTP_RESEND_WAIT');
  if (doc.sends >= config.otp.maxSends) {
    await OtpChallenge.deleteOne({ _id: doc._id });
    throw tooMany('Bạn đã yêu cầu gửi lại mã quá nhiều lần, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
  }
  const user = await User.findById(doc.user);
  if (!user) throw badRequest('Phiên xác thực đã hết hạn, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
  const code = newCode();
  doc.codeHash = await bcrypt.hash(code, 8);
  doc.expiresAt = new Date(Date.now() + config.otp.minutes * 60000);
  doc.attempts = 0;
  doc.sends += 1;
  doc.lastSentAt = new Date();
  await doc.save();
  const sent = await sendOtpCode(user.email, user.name, code, doc.purpose);
  res.json({
    message: 'Đã gửi lại mã OTP.',
    expiresIn: config.otp.minutes * 60,
    resendAfter: config.otp.resendSeconds,
    devCode: !sent && !config.isProduction ? code : undefined,
  });
}));

// Đổi refresh token lấy access token mới (refresh token cũ bị thu hồi).
router.post('/refresh', limiter, wrap(async (req, res) => {
  const raw = String(req.body.refreshToken || '');
  const doc = raw ? await RefreshToken.findOne({ tokenHash: sha(raw) }) : null;
  if (!doc || doc.expiresAt < new Date()) throw unauthorized('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.');
  const user = await User.findById(doc.user);
  await RefreshToken.deleteOne({ _id: doc._id });
  if (!user || user.tokenVersion !== doc.version) throw unauthorized('Phiên đăng nhập đã bị thu hồi.');
  res.json(await session(user, doc.sid || undefined));
}));

// Xác thực email bằng mã 6 số
router.post('/verify-email', requireAuth, limiter, wrap(async (req, res) => {
  const u = req.user;
  if (u.emailVerified) return res.json({ user: u.toJSON() });
  const code = String(req.body.code || '').trim();
  if (!u.verifyCodeHash || !u.verifyCodeExpires || u.verifyCodeExpires < new Date()
    || !(await bcrypt.compare(code, u.verifyCodeHash))) {
    throw badRequest('Mã xác thực không đúng hoặc đã hết hạn.', 'INVALID_CODE');
  }
  u.emailVerified = true;
  u.verifyCodeHash = null;
  u.verifyCodeExpires = null;
  await u.save();
  res.json({ user: u.toJSON() });
}));

router.post('/resend-verification', requireAuth, limiter, wrap(async (req, res) => {
  if (req.user.emailVerified) return res.json({ message: 'Email đã được xác thực.' });
  const devCode = await issueVerifyCode(req.user);
  res.json({ message: 'Đã gửi mã xác thực.', devCode });
}));

// Quên mật khẩu: gửi mã 6 số qua email
router.post('/forgot-password', limiter, wrap(async (req, res) => {
  const mail = email(req.body.email);
  const user = await User.findOne({ email: mail });
  const body = { message: 'Nếu email đã đăng ký, mã khôi phục đã được gửi.' };
  if (user) {
    const code = newCode();
    user.resetCodeHash = await bcrypt.hash(code, 8);
    user.resetCodeExpires = new Date(Date.now() + config.resetCodeMinutes * 60 * 1000);
    user.resetAttempts = 0;
    await user.save();
    const sent = await sendResetCode(mail, user.name, code);
    // Chế độ phát triển, chưa cấu hình SMTP: trả mã để demo/kiểm thử.
    if (!sent && !config.isProduction) body.devCode = code;
  }
  body.mailEnabled = mailEnabled();
  res.json(body);
}));

// Đặt lại mật khẩu bằng mã khôi phục
router.post('/reset-password', limiter, wrap(async (req, res) => {
  const mail = email(req.body.email);
  const code = otpCode(req.body.code);
  const pass = password(req.body.newPassword, 'Mật khẩu mới', mail);
  const user = await User.findOne({ email: mail });
  const invalid = badRequest('Mã khôi phục không đúng hoặc đã hết hạn.', 'INVALID_CODE');
  if (!user || !user.resetCodeHash || !user.resetCodeExpires || user.resetCodeExpires < new Date()) throw invalid;
  if (user.resetAttempts >= 5) throw badRequest('Bạn đã nhập sai quá nhiều lần, hãy yêu cầu mã mới.', 'INVALID_CODE');
  if (!(await bcrypt.compare(code, user.resetCodeHash))) {
    user.resetAttempts += 1;
    await user.save();
    throw invalid;
  }
  user.passwordHash = await bcrypt.hash(pass, 10);
  user.resetCodeHash = null;
  user.resetCodeExpires = null;
  user.resetAttempts = 0;
  await revokeAll(user); // thu hồi các phiên cũ
  user.emailVerified = true; // nhận được mã qua email nghĩa là email hợp lệ
  user.failedLogins = 0;
  user.lockUntil = null;
  await user.save();
  res.json(await session(user));
}));

router.get('/me', requireAuth, (req, res) => res.json({ user: req.user.toJSON() }));

// Cập nhật hồ sơ và tùy chọn hiển thị
router.put('/me', requireAuth, wrap(async (req, res) => {
  const u = req.user;
  if (req.body.name !== undefined) u.name = fullName(req.body.name);
  if (req.body.currency !== undefined) {
    if (!CURRENCIES.includes(req.body.currency)) throw badRequest('Đơn vị tiền tệ không được hỗ trợ.');
    u.currency = req.body.currency;
  }
  if (req.body.hideBalance !== undefined) u.hideBalance = req.body.hideBalance === true;
  if (req.body.rates && typeof req.body.rates === 'object') {
    const rates = {};
    for (const [k, v] of Object.entries(req.body.rates)) {
      if (CURRENCIES.includes(k) && Number.isFinite(Number(v)) && Number(v) > 0) rates[k] = Number(v);
    }
    u.rates = rates;
  }
  await u.save();
  res.json({ user: u.toJSON() });
}));

// Đổi mật khẩu: xác thực mật khẩu cũ
router.put('/change-password', requireAuth, limiter, wrap(async (req, res) => {
  const u = req.user;
  if (!(await bcrypt.compare(String(req.body.oldPassword || ''), u.passwordHash))) {
    throw badRequest('Mật khẩu hiện tại không đúng.', 'WRONG_PASSWORD');
  }
  const pass = password(req.body.newPassword, 'Mật khẩu mới', u.email);
  if (pass === req.body.oldPassword) throw badRequest('Mật khẩu mới phải khác mật khẩu hiện tại.');
  u.passwordHash = await bcrypt.hash(pass, 10);
  await revokeAll(u);
  await u.save();
  res.json(await session(u));
}));

// Đăng xuất thiết bị hiện tại (chỉ thu hồi phiên của thiết bị này).
// { all: true } → đăng xuất khỏi mọi thiết bị.
router.post('/logout', requireAuth, wrap(async (req, res) => {
  if (req.body?.all === true || !req.sessionId) {
    await revokeAll(req.user);
    await req.user.save();
  } else {
    await RefreshToken.deleteMany({ user: req.user._id, sid: req.sessionId });
  }
  res.status(204).end();
}));

// Xóa tài khoản và toàn bộ dữ liệu (yêu cầu mật khẩu)
router.delete('/me', requireAuth, wrap(async (req, res) => {
  const u = req.user;
  if (!(await bcrypt.compare(String(req.body.password || ''), u.passwordHash))) {
    throw badRequest('Mật khẩu không đúng.', 'WRONG_PASSWORD');
  }
  await Promise.all([Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken, OtpChallenge, PaymentRequest, BankEvent]
    .map((M) => M.deleteMany({ user: u._id })));
  await User.deleteOne({ _id: u._id });
  res.status(204).end();
}));

module.exports = router;
