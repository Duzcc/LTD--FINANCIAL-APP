// Tích hợp mô hình ngôn ngữ (LLM) cho trợ lý tài chính.
// Hỗ trợ Anthropic Claude (Messages API) và mọi máy chủ tương thích OpenAI
// (OpenAI, Azure OpenAI, Ollama, LM Studio…). Không cấu hình → trả lời bằng luật.
const config = require('../config');
const L = require('./ledger');
const { isIncome, isExpense, isDebt } = require('./constants');
const { ApiError } = require('./errors');

const sum = (list) => list.reduce((s, e) => s + e.amount, 0);
const round = (v) => Math.round(v);

/** Tóm tắt số liệu (không chứa thông tin đăng nhập) để làm ngữ cảnh cho mô hình. */
function financialContext(state, user, now = new Date()) {
  const cur = user.currency || 'VND';
  const inCur = (e) => L.byId(state.wallets, e.walletId)?.currency === cur;
  const monthOf = (offset) => new Date(now.getFullYear(), now.getMonth() - offset, 1);
  const months = [0, 1, 2, 3].map((i) => {
    const m = monthOf(i);
    const list = state.entries.filter((e) => !e.excluded && inCur(e) && L.sameMonth(new Date(e.date), m));
    return {
      month: `${m.getMonth() + 1}/${m.getFullYear()}`,
      income: round(sum(list.filter((e) => isIncome(e.kind)))),
      expense: round(sum(list.filter((e) => isExpense(e.kind)))),
      byCategory: state.categories
        .map((c) => ({ name: c.name, amount: round(sum(list.filter((e) => e.categoryId === c.id && (c.income ? isIncome(e.kind) : isExpense(e.kind))))) }))
        .filter((x) => x.amount > 0)
        .sort((a, b) => b.amount - a.amount)
        .slice(0, 8),
    };
  });
  const thisMonth = monthOf(0);
  return {
    today: now.toISOString().slice(0, 10),
    dayOfMonth: now.getDate(),
    daysInMonth: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate(),
    currency: cur,
    wallets: state.wallets.map((w) => ({ name: w.name, type: w.savings ? 'tiết kiệm' : 'cơ bản', currency: w.currency, balance: round(L.balance(state, w.id)), target: w.target || undefined })),
    months,
    budgets: state.budgets.filter((b) => L.sameMonth(L.monthValue(b.month), thisMonth)).map((b) => ({
      category: b.categoryId ? L.byId(state.categories, b.categoryId)?.name : (b.income ? 'Mục tiêu thu cả tháng' : 'Tổng chi cả tháng'),
      limit: round(b.amount),
      used: round(L.used(state, b)),
    })),
    debts: state.people.map((p) => ({
      person: p.name,
      theyOweMe: round(L.outstanding(state, { borrowed: false, personId: p.id, currency: cur })),
      iOwe: round(L.outstanding(state, { borrowed: true, personId: p.id, currency: cur })),
      nextDue: state.entries.filter((e) => isDebt(e.kind) && e.personId === p.id && e.dueDate).map((e) => new Date(e.dueDate).toISOString().slice(0, 10)).sort()[0],
    })).filter((d) => d.theyOweMe > 0 || d.iOwe > 0),
    recurring: (state.recurring || []).filter((r) => r.active).map((r) => ({ note: r.note, amount: r.amount, frequency: r.frequency })),
  };
}

const SYSTEM = `Bạn là trợ lý tài chính cá nhân trong ứng dụng "Quản lý chi tiêu" của người dùng Việt Nam.
- Chỉ dựa vào dữ liệu JSON được cung cấp; nếu thiếu dữ liệu, nói rõ.
- Trả lời bằng tiếng Việt, ngắn gọn (tối đa khoảng 150 từ), dùng số có dấu chấm phân tách hàng nghìn và đơn vị tiền tệ.
- Có thể phân tích thói quen, gợi ý cắt giảm, lập kế hoạch tiết kiệm (ví dụ quy tắc 50/30/20).
- Không đưa ra khuyến nghị mua/bán chứng khoán, tiền mã hóa hay sản phẩm tài chính cụ thể; nhắc người dùng tham khảo chuyên gia khi cần.
- Không bịa đặt số liệu.`;

function sanitizeMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) throw new ApiError(400, 'Thiếu nội dung câu hỏi.', 'VALIDATION_ERROR');
  const list = messages.slice(-12).map((m) => ({
    role: m && m.role === 'assistant' ? 'assistant' : 'user',
    content: String((m && m.content) || '').slice(0, 2000),
  })).filter((m) => m.content.trim());
  while (list.length && list[0].role !== 'user') list.shift();
  if (!list.length || list[list.length - 1].role !== 'user') throw new ApiError(400, 'Tin nhắn cuối phải là câu hỏi.', 'VALIDATION_ERROR');
  return list;
}

const aiEnabled = () => ['anthropic', 'openai'].includes(config.ai.provider) && !!config.ai.model
  && (config.ai.provider === 'openai' ? !!config.ai.baseUrl || !!config.ai.apiKey : !!config.ai.apiKey);

async function callModel(messages, context) {
  const system = `${SYSTEM}\n\nDữ liệu tài chính hiện tại (JSON):\n${JSON.stringify(context)}`;
  const ai = config.ai;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    if (ai.provider === 'anthropic') {
      const r = await fetch(`${ai.baseUrl || 'https://api.anthropic.com'}/v1/messages`, {
        method: 'POST',
        signal: controller.signal,
        headers: { 'content-type': 'application/json', 'x-api-key': ai.apiKey, 'anthropic-version': '2023-06-01' },
        body: JSON.stringify({ model: ai.model, max_tokens: ai.maxTokens, system, messages }),
      });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data?.error?.message || `HTTP ${r.status}`);
      return (data.content || []).filter((c) => c.type === 'text').map((c) => c.text).join('\n').trim();
    }
    const base = (ai.baseUrl || 'https://api.openai.com/v1').replace(/\/$/, '');
    const r = await fetch(`${base}/chat/completions`, {
      method: 'POST',
      signal: controller.signal,
      headers: { 'content-type': 'application/json', ...(ai.apiKey ? { authorization: `Bearer ${ai.apiKey}` } : {}) },
      body: JSON.stringify({ model: ai.model, max_tokens: ai.maxTokens, messages: [{ role: 'system', content: system }, ...messages] }),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data?.error?.message || `HTTP ${r.status}`);
    return String(data?.choices?.[0]?.message?.content || '').trim();
  } finally {
    clearTimeout(timer);
  }
}

/** Câu trả lời dự phòng không dùng mô hình (app sẽ dùng trợ lý trên thiết bị). */
function rulesReply(context) {
  const m = context.months[0];
  return `Tháng ${m.month}: thu ${m.income.toLocaleString('vi-VN')} ${context.currency}, chi ${m.expense.toLocaleString('vi-VN')} ${context.currency}. Máy chủ chưa cấu hình mô hình AI nên câu trả lời chi tiết được tạo trên thiết bị.`;
}

module.exports = { financialContext, sanitizeMessages, callModel, rulesReply, aiEnabled };
