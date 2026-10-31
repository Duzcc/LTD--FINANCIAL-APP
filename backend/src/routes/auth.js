const router = require('express').Router();
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const config = require('../config');
const wrap = require('../middleware/async');
const { requireAuth, signToken } = require('../middleware/auth');
const { User, Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken } = require('../models');
const { defaultWallets, defaultCategories, defaultPeople } = require('../services/defaults');
const { badRequest, conflict, unauthorized } = require('../services/errors');
const { sendResetCode, sendVerifyCode, mailEnabled } = require('../services/mailer');
const { CURRENCIES } = require('../services/constants');

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: Number(process.env.AUTH_RATE_LIMIT) || 50,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: { code: 'TOO_MANY_REQUESTS', message: 'Bạn thử quá nhiều lần, vui lòng đợi ít phút.' } },
});

function email(v) {
  const e = String(v || '').trim().toLowerCase();
  if (!EMAIL.test(e)) throw badRequest('Email không hợp lệ.');
  return e;
}
function password(v, field = 'Mật khẩu') {
  const p = String(v || '');
  if (p.length < 6) throw badRequest(`${field} phải có ít nhất 6 ký tự.`);
  if (p.length > 72) throw badRequest(`${field} tối đa 72 ký tự.`);
  return p;
}
const sha = (v) => crypto.createHash('sha256').update(v).digest('hex');

// Cấp cặp token: access token (JWT, ngắn hạn) + refresh token (ngẫu nhiên, dài hạn, xoay vòng).
async function session(user) {
  const refreshToken = crypto.randomBytes(48).toString('base64url');
  await RefreshToken.create({
    user: user._id,
    tokenHash: sha(refreshToken),
    version: user.tokenVersion,
    expiresAt: new Date(Date.now() + config.refreshDays * 86400000),
  });
  return { token: signToken(user), refreshToken, user: user.toJSON() };
}

async function revokeAll(user) {
  user.tokenVersion += 1;
  await RefreshToken.deleteMany({ user: user._id });
}

// Tạo mã xác thực email 6 số; trả mã ở chế độ dev khi chưa cấu hình SMTP.
async function issueVerifyCode(user) {
  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
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

// Đăng ký bằng email
router.post('/register', limiter, wrap(async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (!name) throw badRequest('Vui lòng nhập họ tên.');
  const mail = email(req.body.email);
  const pass = password(req.body.password);
  if (await User.exists({ email: mail })) throw conflict('Email đã được đăng ký.', 'EMAIL_EXISTS');
  const user = await User.create({ name, email: mail, passwordHash: await bcrypt.hash(pass, 10) });
  if (req.body.seedDefaults !== false) await seedDefaults(user._id);
  const devVerificationCode = await issueVerifyCode(user);
  res.status(201).json({ ...(await session(user)), devVerificationCode });
}));

// Đăng nhập
router.post('/login', limiter, wrap(async (req, res) => {
  const mail = String(req.body.email || '').trim().toLowerCase();
  const user = await User.findOne({ email: mail });
  const ok = user && (await bcrypt.compare(String(req.body.password || ''), user.passwordHash));
  if (!ok) throw unauthorized('Email hoặc mật khẩu không đúng.');
  res.json(await session(user));
}));

// Đổi refresh token lấy access token mới (refresh token cũ bị thu hồi).
router.post('/refresh', limiter, wrap(async (req, res) => {
  const raw = String(req.body.refreshToken || '');
  const doc = raw ? await RefreshToken.findOne({ tokenHash: sha(raw) }) : null;
  if (!doc || doc.expiresAt < new Date()) throw unauthorized('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.');
  const user = await User.findById(doc.user);
  await RefreshToken.deleteOne({ _id: doc._id });
  if (!user || user.tokenVersion !== doc.version) throw unauthorized('Phiên đăng nhập đã bị thu hồi.');
  res.json(await session(user));
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
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
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
  const code = String(req.body.code || '').trim();
  const pass = password(req.body.newPassword, 'Mật khẩu mới');
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
  await user.save();
  res.json(await session(user));
}));

router.get('/me', requireAuth, (req, res) => res.json({ user: req.user.toJSON() }));

// Cập nhật hồ sơ và tùy chọn hiển thị
router.put('/me', requireAuth, wrap(async (req, res) => {
  const u = req.user;
  if (req.body.name !== undefined) {
    const name = String(req.body.name).trim();
    if (!name) throw badRequest('Vui lòng nhập họ tên.');
    u.name = name;
  }
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
  const pass = password(req.body.newPassword, 'Mật khẩu mới');
  if (pass === req.body.oldPassword) throw badRequest('Mật khẩu mới phải khác mật khẩu hiện tại.');
  u.passwordHash = await bcrypt.hash(pass, 10);
  await revokeAll(u);
  await u.save();
  res.json(await session(u));
}));

// Đăng xuất: thu hồi mọi token đã cấp của tài khoản
router.post('/logout', requireAuth, wrap(async (req, res) => {
  await revokeAll(req.user);
  await req.user.save();
  res.status(204).end();
}));

// Xóa tài khoản và toàn bộ dữ liệu (yêu cầu mật khẩu)
router.delete('/me', requireAuth, wrap(async (req, res) => {
  const u = req.user;
  if (!(await bcrypt.compare(String(req.body.password || ''), u.passwordHash))) {
    throw badRequest('Mật khẩu không đúng.', 'WRONG_PASSWORD');
  }
  await Promise.all([Wallet, Category, Person, Transaction, Budget, Recurring, RefreshToken]
    .map((M) => M.deleteMany({ user: u._id })));
  await User.deleteOne({ _id: u._id });
  res.status(204).end();
}));

module.exports = router;
