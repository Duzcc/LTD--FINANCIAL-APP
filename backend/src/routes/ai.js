// API AI cho ứng dụng. Backend xác thực người dùng, dựng snapshot dữ liệu rồi chuyển tiếp sang AI service.
// Khi AI service không khả dụng: /chat lùi về LLM trực tiếp hoặc trợ lý luật (services/ai.js);
// các API khác trả 503 AI_UNAVAILABLE để ứng dụng dùng mô hình trên thiết bị.
const express = require('express');
const rateLimit = require('express-rate-limit');
const wrap = require('../middleware/async');
const { loadState } = require('../services/store');
const { buildSnapshot, labeledHistory, localIso } = require('../services/aiSnapshot');
const { badRequest } = require('../services/errors');
const legacy = require('../services/ai');
const aiService = require('../clients/aiServiceClient');
const config = require('../config');

const router = express.Router();
const limiter = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.AI_RATE_LIMIT) || 30,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => String(req.user?._id || req.ip),
  message: { error: { code: 'TOO_MANY_REQUESTS', message: 'Bạn thao tác quá nhanh, vui lòng đợi một chút.' } },
});
router.use(limiter);

const text = (v, field, max = 500) => {
  if (typeof v !== 'string' || !v.trim()) throw badRequest(`Thiếu ${field}.`);
  return v.trim().slice(0, max);
};
const opts = (req) => ({ requestId: req.get('x-request-id') });
const snapshotOf = async (req) => buildSnapshot(await loadState(req.user._id), req.user);

// Trạng thái AI để ứng dụng biết dùng mô hình ở máy chủ hay trên thiết bị.
router.get('/status', wrap(async (_req, res) => {
  let service = null;
  if (aiService.enabled()) {
    try { service = await aiService.health(); } catch { service = { status: 'down' }; }
  }
  const llm = legacy.aiEnabled();
  res.json({
    enabled: Boolean(service?.status === 'ok') || llm,
    service: service ? { status: service.status, version: service.version, assistant: service.assistant } : null,
    provider: service?.status === 'ok' ? 'ai-service' : llm ? config.ai.provider : null,
    model: llm ? config.ai.model : null,
    features: service?.status === 'ok'
      ? ['chat', 'categorize', 'parse', 'forecast', 'anomalies', 'budgets', 'search', 'receipts']
      : ['chat'],
  });
}));

// Trợ lý hội thoại: { messages: [{ role, content }] }
router.post('/chat', wrap(async (req, res) => {
  const messages = legacy.sanitizeMessages(req.body.messages);
  const state = await loadState(req.user._id);
  if (aiService.enabled()) {
    try {
      const r = await aiService.chat({ snapshot: buildSnapshot(state, req.user), messages }, opts(req));
      return res.json({ reply: r.reply, source: 'ai-service', provider: r.provider, toolsUsed: r.toolsUsed, actions: r.actions });
    } catch (e) {
      if (e.code !== 'AI_UNAVAILABLE') throw e;
    }
  }
  const context = legacy.financialContext(state, req.user);
  if (!legacy.aiEnabled()) return res.json({ reply: legacy.rulesReply(context), source: 'rules', actions: [] });
  try {
    const reply = await legacy.callModel(messages, context);
    if (!reply) throw new Error('empty');
    res.json({ reply, source: 'llm', model: config.ai.model, actions: [] });
  } catch (e) {
    if (!config.isProduction) console.warn('AI lỗi:', e.message);
    res.json({ reply: legacy.rulesReply(context), source: 'rules', actions: [], error: 'AI tạm thời không phản hồi.' });
  }
}));

// Gợi ý danh mục cá nhân hóa: { text, income? }
router.post('/categorize', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  const r = await aiService.categorize({
    text: text(req.body.text, 'ghi chú'), income: typeof req.body.income === 'boolean' ? req.body.income : null,
    categories: state.categories.map((c) => ({ id: c.id, name: c.name, income: Boolean(c.income) })),
    history: labeledHistory(state), topK: 3,
  }, opts(req));
  res.json(r);
}));

// Nhập nhanh bằng câu tự nhiên: { text }
router.post('/parse', wrap(async (req, res) => {
  const s = await snapshotOf(req);
  const r = await aiService.parse({
    text: text(req.body.text, 'nội dung'), now: s.now, categories: s.categories, people: s.people, wallets: s.wallets,
    history: s.transactions.filter((t) => t.note && t.categoryId).slice(-2000).map((t) => ({ text: t.note, categoryId: t.categoryId })),
  }, opts(req));
  res.json(r);
}));

router.get('/forecast', wrap(async (req, res) => res.json(await aiService.forecast(await snapshotOf(req), opts(req)))));
router.get('/anomalies', wrap(async (req, res) => res.json(await aiService.anomalies(await snapshotOf(req), opts(req)))));

router.get('/budgets/recommend', wrap(async (req, res) => {
  const savingsRate = req.query.savingsRate == null ? 0.2 : Number(req.query.savingsRate);
  if (!(savingsRate >= 0 && savingsRate <= 0.6)) throw badRequest('savingsRate phải trong khoảng 0–0.6.');
  const monthlyIncome = req.query.monthlyIncome == null ? null : Number(req.query.monthlyIncome);
  res.json(await aiService.recommendBudgets({ snapshot: await snapshotOf(req), savingsRate, monthlyIncome }, opts(req)));
}));

// Tổng hợp cho màn hình chính: dự báo + bất thường + gợi ý ngân sách (chạy song song, phần nào lỗi thì bỏ qua)
router.get('/insights', wrap(async (req, res) => {
  const snapshot = await snapshotOf(req);
  const [forecast, anomalies, budgets] = await Promise.allSettled([
    aiService.forecast(snapshot, opts(req)), aiService.anomalies(snapshot, opts(req)),
    aiService.recommendBudgets({ snapshot }, opts(req)),
  ]);
  const ok = (r) => (r.status === 'fulfilled' ? r.value : null);
  if (![forecast, anomalies, budgets].some((r) => r.status === 'fulfilled')) throw forecast.reason;
  res.json({ generatedAt: localIso(), forecast: ok(forecast), anomalies: ok(anomalies), budgets: ok(budgets) });
}));

// Tìm kiếm bằng câu tự nhiên: { query }
router.post('/search', wrap(async (req, res) => {
  const r = await aiService.search({ snapshot: await snapshotOf(req), query: text(req.body.query, 'từ khóa', 200), limit: 50 }, opts(req));
  res.json(r);
}));

// Hóa đơn từ văn bản nhận dạng trên điện thoại: { text }
router.post('/receipts/text', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  res.json(await aiService.receiptText({
    text: text(req.body.text, 'nội dung hóa đơn', 20000),
    categories: state.categories.map((c) => ({ id: c.id, name: c.name, income: Boolean(c.income) })),
  }, opts(req)));
}));

// Hóa đơn từ ảnh: { image: base64, mediaType: 'image/jpeg' | 'image/png' | 'image/webp' }
router.post('/receipts/scan', wrap(async (req, res) => {
  const { image, mediaType = 'image/jpeg' } = req.body || {};
  if (typeof image !== 'string' || !image) throw badRequest('Thiếu ảnh hóa đơn.');
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(mediaType)) throw badRequest('Chỉ hỗ trợ ảnh JPEG/PNG/WebP.');
  const buf = Buffer.from(image, 'base64');
  if (!buf.length || buf.length > 6 * 1024 * 1024) throw badRequest('Ảnh rỗng hoặc lớn hơn 6MB.');
  const state = await loadState(req.user._id);
  const form = new FormData();
  form.append('image', new Blob([buf], { type: mediaType }), 'receipt');
  form.append('categories', JSON.stringify(state.categories.map((c) => ({ id: c.id, name: c.name, income: Boolean(c.income) }))));
  res.json(await aiService.receiptScan(form, opts(req)));
}));

module.exports = router;
