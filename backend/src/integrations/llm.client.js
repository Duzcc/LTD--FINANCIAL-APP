const config = require('../config');

const SYSTEM_PROMPT = `Bạn là trợ lý tài chính cá nhân trong ứng dụng "Quản lý chi tiêu" của người dùng Việt Nam.
- Chỉ dựa vào dữ liệu JSON được cung cấp; nếu thiếu dữ liệu, nói rõ.
- Trả lời bằng tiếng Việt, ngắn gọn (tối đa khoảng 150 từ), dùng số có dấu chấm phân tách hàng nghìn và đơn vị tiền tệ.
- Có thể phân tích thói quen, gợi ý cắt giảm, lập kế hoạch tiết kiệm (ví dụ quy tắc 50/30/20).
- Không đưa ra khuyến nghị mua/bán chứng khoán, tiền mã hóa hay sản phẩm tài chính cụ thể; nhắc người dùng tham khảo chuyên gia khi cần.
- Không bịa đặt số liệu.`;

const TIMEOUT_MS = 30000;

function enabled() {
  const { provider, model, apiKey, baseUrl } = config.ai;
  if (!model) return false;
  if (provider === 'anthropic') return Boolean(apiKey);
  if (provider === 'openai') return Boolean(baseUrl || apiKey);
  return false;
}

async function postJson(url, headers, body) {
  const res = await fetch(url, {
    method: 'POST',
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data?.error?.message || `HTTP ${res.status}`);
  return data;
}

async function askAnthropic(system, messages) {
  const { apiKey, baseUrl, model, maxTokens } = config.ai;
  const data = await postJson(
    `${baseUrl || 'https://api.anthropic.com'}/v1/messages`,
    { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
    { model, max_tokens: maxTokens, system, messages },
  );
  return (data.content || []).filter((c) => c.type === 'text').map((c) => c.text).join('\n').trim();
}

async function askOpenAi(system, messages) {
  const { apiKey, baseUrl, model, maxTokens } = config.ai;
  const data = await postJson(
    `${(baseUrl || 'https://api.openai.com/v1').replace(/\/$/, '')}/chat/completions`,
    apiKey ? { authorization: `Bearer ${apiKey}` } : {},
    { model, max_tokens: maxTokens, messages: [{ role: 'system', content: system }, ...messages] },
  );
  return String(data?.choices?.[0]?.message?.content || '').trim();
}

function ask(messages, context) {
  const system = `${SYSTEM_PROMPT}\n\nDữ liệu tài chính hiện tại (JSON):\n${JSON.stringify(context)}`;
  return config.ai.provider === 'anthropic' ? askAnthropic(system, messages) : askOpenAi(system, messages);
}

module.exports = { enabled, ask };
