const config = require('../config');
const ledger = require('./ledger.service');
const aiService = require('../integrations/ai-service.client');
const llm = require('../integrations/llm.client');
const { buildSnapshot, labeledHistory } = require('../domain/snapshot');
const { financialContext, rulesReply } = require('../domain/financial-context');
const validate = require('../validators/ai.validator');
const { localIso } = require('../utils/time');

const SERVICE_FEATURES = ['chat', 'categorize', 'parse', 'forecast', 'anomalies', 'budgets', 'search', 'receipts'];

const categoriesOf = (state) => state.categories.map((c) => ({ id: c.id, name: c.name, income: Boolean(c.income) }));
const snapshotOf = async (user) => buildSnapshot(await ledger.loadState(user._id), user);

async function status() {
  const service = aiService.enabled() ? await aiService.health().catch(() => ({ status: 'down' })) : null;
  const serviceUp = service?.status === 'ok';
  const llmEnabled = llm.enabled();
  return {
    enabled: serviceUp || llmEnabled,
    service: service ? { status: service.status, version: service.version, assistant: service.assistant } : null,
    provider: serviceUp ? 'ai-service' : llmEnabled ? config.ai.provider : null,
    model: llmEnabled ? config.ai.model : null,
    features: serviceUp ? SERVICE_FEATURES : ['chat'],
  };
}

async function chatWithLlm(messages, context) {
  if (!llm.enabled()) return { reply: rulesReply(context), source: 'rules', actions: [] };
  const reply = await llm.ask(messages, context).catch((e) => {
    if (!config.isProduction) console.warn(`llm request failed: ${e.message}`);
    return '';
  });
  if (!reply) return { reply: rulesReply(context), source: 'rules', actions: [], error: 'AI tạm thời không phản hồi.' };
  return { reply, source: 'llm', model: config.ai.model, actions: [] };
}

async function chat(user, body, requestId) {
  const messages = validate.chatMessages(body.messages);
  const state = await ledger.loadState(user._id);
  if (aiService.enabled()) {
    const r = await aiService.chat({ snapshot: buildSnapshot(state, user), messages }, { requestId }).catch((e) => {
      if (e.code !== 'AI_UNAVAILABLE') throw e;
      return null;
    });
    if (r) return { reply: r.reply, source: 'ai-service', provider: r.provider, toolsUsed: r.toolsUsed, actions: r.actions };
  }
  return chatWithLlm(messages, financialContext(state, user));
}

async function categorize(user, body, requestId) {
  const state = await ledger.loadState(user._id);
  return aiService.categorize({
    text: validate.requiredText(body.text, 'ghi chú'),
    income: typeof body.income === 'boolean' ? body.income : null,
    categories: categoriesOf(state),
    history: labeledHistory(state),
    topK: 3,
  }, { requestId });
}

async function parse(user, body, requestId) {
  const s = await snapshotOf(user);
  return aiService.parse({
    text: validate.requiredText(body.text, 'nội dung'),
    now: s.now,
    categories: s.categories,
    people: s.people,
    wallets: s.wallets,
    history: s.transactions
      .filter((t) => t.note && t.categoryId)
      .slice(-2000)
      .map((t) => ({ text: t.note, categoryId: t.categoryId })),
  }, { requestId });
}

const forecast = async (user, requestId) => aiService.forecast(await snapshotOf(user), { requestId });
const anomalies = async (user, requestId) => aiService.anomalies(await snapshotOf(user), { requestId });

async function recommendBudgets(user, query, requestId) {
  const { savingsRate, monthlyIncome } = validate.budgetQuery(query);
  return aiService.recommendBudgets({ snapshot: await snapshotOf(user), savingsRate, monthlyIncome }, { requestId });
}

async function insights(user, requestId) {
  const snapshot = await snapshotOf(user);
  const results = await Promise.allSettled([
    aiService.forecast(snapshot, { requestId }),
    aiService.anomalies(snapshot, { requestId }),
    aiService.recommendBudgets({ snapshot }, { requestId }),
  ]);
  if (results.every((r) => r.status === 'rejected')) throw results[0].reason;
  const [forecastResult, anomaliesResult, budgetsResult] = results.map((r) => (r.status === 'fulfilled' ? r.value : null));
  return { generatedAt: localIso(), forecast: forecastResult, anomalies: anomaliesResult, budgets: budgetsResult };
}

async function search(user, body, requestId) {
  return aiService.search({
    snapshot: await snapshotOf(user),
    query: validate.requiredText(body.query, 'từ khóa', 200),
    limit: 50,
  }, { requestId });
}

async function receiptFromText(user, body, requestId) {
  const state = await ledger.loadState(user._id);
  return aiService.receiptText({
    text: validate.requiredText(body.text, 'nội dung hóa đơn', 20000),
    categories: categoriesOf(state),
  }, { requestId });
}

async function receiptFromImage(user, body, requestId) {
  const { bytes, mediaType } = validate.receiptImage(body);
  const state = await ledger.loadState(user._id);
  const form = new FormData();
  form.append('image', new Blob([bytes], { type: mediaType }), 'receipt');
  form.append('categories', JSON.stringify(categoriesOf(state)));
  return aiService.receiptScan(form, { requestId });
}

module.exports = {
  status, chat, categorize, parse, forecast, anomalies, recommendBudgets, insights, search, receiptFromText, receiptFromImage,
};
