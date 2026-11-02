// Kết nối ngân hàng: nhận tiền bằng VietQR và đối soát tự động qua webhook SePay (sepay.vn).
// Luồng: app tạo yêu cầu nhận tiền → mã đối soát nằm trong nội dung chuyển khoản của QR →
// người chuyển quét QR → SePay thấy tiền vào tài khoản và gọi webhook → backend ghi giao dịch.
const router = require('express').Router();
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const config = require('../config');
const wrap = require('../middleware/async');
const { requireAuth } = require('../middleware/auth');
const { User, PaymentRequest, BankEvent } = require('../models');
const { loadState, upsert } = require('../services/store');
const L = require('../services/ledger');
const { BANKS } = require('../services/banks');
const { badRequest, notFound, unauthorized } = require('../services/errors');

const sha = (v) => crypto.createHash('sha256').update(v).digest('hex');
// Bỏ các ký tự dễ nhầm (O/0, I/1) vì người dùng có thể phải gõ lại mã khi chuyển khoản tay.
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE = /LTD[A-HJ-NP-Z2-9]{6}/;
const newCode = () => `LTD${Array.from({ length: 6 }, () => ALPHABET[crypto.randomInt(ALPHABET.length)]).join('')}`;

const webhookLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.WEBHOOK_RATE_LIMIT) || 120,
  standardHeaders: true,
  legacyHeaders: false,
});

const webhookUrl = (req) => `${config.publicUrl || `${req.protocol}://${req.get('host')}`}/api/bank/sepay/webhook`;

router.get('/banks', (_req, res) => res.json({ items: BANKS }));

// ------------------------------------------------------------ cấu hình SePay
router.get('/sepay', requireAuth, (req, res) => res.json({
  connected: !!req.user.sepayKeyHash,
  keyHint: req.user.sepayKeyHint,
  webhookUrl: webhookUrl(req),
}));

// Tạo (hoặc thay) API key cho webhook. Khóa chỉ hiện một lần; máy chủ chỉ lưu bản băm.
router.post('/sepay/key', requireAuth, wrap(async (req, res) => {
  const apiKey = `ltd_${crypto.randomBytes(24).toString('base64url')}`;
  req.user.sepayKeyHash = sha(apiKey);
  req.user.sepayKeyHint = apiKey.slice(-4);
  await req.user.save();
  res.status(201).json({ apiKey, keyHint: req.user.sepayKeyHint, webhookUrl: webhookUrl(req) });
}));

router.delete('/sepay/key', requireAuth, wrap(async (req, res) => {
  req.user.sepayKeyHash = null;
  req.user.sepayKeyHint = null;
  await req.user.save();
  res.status(204).end();
}));

// ------------------------------------------------------- yêu cầu nhận tiền
router.get('/requests', requireAuth, wrap(async (req, res) => {
  const filter = { user: req.user._id };
  if (req.query.walletId) filter.walletId = String(req.query.walletId);
  const items = await PaymentRequest.find(filter).sort({ createdAt: -1 }).limit(50);
  res.json({ items: items.map((r) => r.toJSON()) });
}));

router.get('/requests/:id', requireAuth, wrap(async (req, res) => {
  const r = await PaymentRequest.findOne({ _id: req.params.id, user: req.user._id }).catch(() => null);
  if (!r) throw notFound();
  res.json(r.toJSON());
}));

router.post('/requests', requireAuth, wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  const wallet = L.byId(state.wallets, String(req.body.walletId || ''));
  if (!wallet) throw badRequest('Vui lòng chọn ví hợp lệ.');
  if (!wallet.bankBin || !wallet.bankAccount) throw badRequest('Ví chưa liên kết tài khoản ngân hàng.');
  const kind = req.body.kind === 'collect' ? 'collect' : 'income';
  let amount = null;
  if (req.body.amount !== undefined && req.body.amount !== null && req.body.amount !== '') {
    amount = Number(req.body.amount);
    if (!Number.isFinite(amount) || amount <= 0) throw badRequest('Số tiền phải lớn hơn 0.');
    if (!Number.isInteger(amount)) throw badRequest('Số tiền VND phải là số nguyên.');
    if (amount > 500000000) throw badRequest('Số tiền tối đa 500.000.000 đ mỗi mã QR.');
  }
  const personId = req.body.personId ? String(req.body.personId) : null;
  let categoryId = req.body.categoryId ? String(req.body.categoryId) : null;
  if (kind === 'collect') {
    if (!personId || !L.byId(state.people, personId)) throw badRequest('Chọn người cần thu nợ.');
    const left = L.outstanding(state, { borrowed: false, personId, currency: 'VND' });
    if (left <= 0) throw badRequest('Người này không còn khoản nợ cần thu.');
    if (!amount) throw badRequest('Nhập số tiền cần thu.');
    if (amount > left) throw badRequest(`Số tiền thu nợ vượt số còn phải thu (${left}).`);
    categoryId = null;
  } else {
    const c = categoryId && L.byId(state.categories, categoryId);
    if (categoryId && (!c || !c.income)) throw badRequest('Chọn danh mục thu nhập phù hợp.');
  }
  const note = String(req.body.note || '').trim().slice(0, 100);
  let doc;
  for (let i = 0; !doc; i += 1) {
    try {
      doc = await PaymentRequest.create({
        user: req.user._id, code: newCode(), walletId: wallet.id, kind, amount, categoryId, personId, note,
        expiresAt: new Date(Date.now() + config.paymentRequestDays * 86400000),
      });
    } catch (e) {
      if (e.code !== 11000 || i >= 4) throw e; // trùng mã (rất hiếm) → sinh lại
    }
  }
  res.status(201).json(doc.toJSON());
}));

router.delete('/requests/:id', requireAuth, wrap(async (req, res) => {
  const r = await PaymentRequest.findOne({ _id: req.params.id, user: req.user._id }).catch(() => null);
  if (!r) throw notFound();
  if (r.status === 'paid') throw badRequest('Yêu cầu đã được thanh toán, không thể hủy.');
  r.status = 'cancelled';
  await r.save();
  res.json(r.toJSON());
}));

// ----------------------------------------------------------- webhook SePay
// Ghi giao dịch cho yêu cầu đã khớp. Thu nợ vượt số còn nợ → ghi thành thu nhập để không mất tiền.
async function recordPayment(user, request, event) {
  const state = await loadState(user);
  const id = `bank_${event.providerId}`.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);
  const note = [request.note || (request.kind === 'collect' ? 'Thu nợ qua VietQR' : 'Nhận tiền qua VietQR'), request.code]
    .filter(Boolean).join(' • ');
  const base = { amount: event.amount, walletId: request.walletId, date: event.occurredAt || new Date(), note };
  const income = () => {
    const category = (request.categoryId && L.byId(state.categories, request.categoryId))
      || state.categories.find((c) => c.income && c.id === 'other_income')
      || state.categories.find((c) => c.income);
    if (!category) throw badRequest('Chưa có danh mục thu nhập.');
    return { ...base, kind: 'income', categoryId: category.id, personId: request.personId };
  };
  let data = request.kind === 'collect' ? { ...base, kind: 'collect', personId: request.personId } : income();
  try {
    await upsert(user, state, 'entries', id, data);
  } catch (e) {
    if (data.kind !== 'collect') throw e;
    data = { ...income(), note: `${note} (vượt số nợ còn lại)` };
    await upsert(user, state, 'entries', id, data);
  }
  return id;
}

router.post('/sepay/webhook', webhookLimiter, wrap(async (req, res) => {
  const [scheme, key] = String(req.headers.authorization || '').split(' ');
  const user = /^apikey$/i.test(scheme || '') && key ? await User.findOne({ sepayKeyHash: sha(key.trim()) }) : null;
  if (!user) throw unauthorized('API key webhook không hợp lệ.');

  const b = req.body || {};
  if (b.id === undefined || b.id === null) throw badRequest('Thiếu mã giao dịch SePay.');
  const amount = Number(b.transferAmount);
  const occurred = b.transactionDate ? new Date(String(b.transactionDate).replace(' ', 'T')) : null;
  const text = `${b.code || ''} ${b.content || ''} ${b.description || ''}`.toUpperCase();
  let event;
  try {
    event = await BankEvent.create({
      user: user._id,
      providerId: String(b.id),
      accountNumber: String(b.accountNumber || ''),
      transferType: b.transferType === 'out' ? 'out' : 'in',
      amount: Number.isFinite(amount) ? amount : 0,
      content: text.slice(0, 500),
      occurredAt: occurred && !Number.isNaN(occurred.getTime()) ? occurred : null,
    });
  } catch (e) {
    if (e.code === 11000) return res.json({ success: true, duplicate: true }); // SePay gửi lại
    throw e;
  }

  const finish = async (result, extra = {}) => {
    event.result = result;
    await event.save();
    res.json({ success: true, result, ...extra });
  };
  if (event.transferType !== 'in' || !(event.amount > 0)) return finish('ignored');
  // Nội dung chuyển khoản có thể bị ngân hàng chèn khoảng trắng/ký tự: so khớp trên chuỗi đã bỏ khoảng trắng.
  const match = CODE.exec(text.replace(/[^A-Z0-9]/g, ''));
  const request = match && await PaymentRequest.findOne({ user: user._id, code: match[0], status: 'pending' });
  if (!request || request.expiresAt < new Date()) return finish('unmatched');
  const state = await loadState(user._id);
  const wallet = L.byId(state.wallets, request.walletId);
  if (!wallet || (event.accountNumber && wallet.bankAccount && event.accountNumber !== wallet.bankAccount)) {
    return finish('unmatched');
  }
  const entryId = await recordPayment(user._id, request, event);
  request.status = 'paid';
  request.paidAmount = event.amount;
  request.paidAt = event.occurredAt || new Date();
  request.entryId = entryId;
  await request.save();
  event.requestId = request._id;
  return finish('matched', { entryId });
}));

module.exports = router;
