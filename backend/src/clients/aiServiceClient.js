// Client gọi AI service (Python/FastAPI) — xác thực bằng khóa dùng chung X-API-Key.
// Mọi lỗi mạng/timeout/5xx được chuẩn hóa thành ApiError 503 AI_UNAVAILABLE để route tự lùi về phương án dự phòng.
const crypto = require('node:crypto');
const config = require('../config');
const { ApiError } = require('../services/errors');

const enabled = () => Boolean(config.aiService.url);

class AiUnavailableError extends ApiError {
  constructor(message = 'Dịch vụ AI tạm thời không khả dụng.', cause) {
    super(503, message, 'AI_UNAVAILABLE');
    this.cause = cause;
  }
}

async function request(path, { method = 'POST', body, form, requestId } = {}) {
  if (!enabled()) throw new AiUnavailableError('Chưa cấu hình AI_SERVICE_URL.');
  const headers = { 'x-request-id': requestId || crypto.randomUUID().slice(0, 12) };
  if (config.aiService.key) headers['x-api-key'] = config.aiService.key;
  let payload;
  if (form) payload = form;
  else if (body !== undefined) {
    headers['content-type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  let res;
  try {
    res = await fetch(config.aiService.url + path, {
      method, headers, body: payload, signal: AbortSignal.timeout(config.aiService.timeoutMs),
    });
  } catch (e) {
    throw new AiUnavailableError(undefined, e);
  }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { /* không phải JSON */ }
  if (res.status >= 500 && res.status !== 501) throw new AiUnavailableError(undefined, new Error(`HTTP ${res.status}`));
  if (!res.ok) {
    const message = data?.error?.message || data?.detail || 'Yêu cầu AI không hợp lệ.';
    const code = res.status === 501 ? 'AI_NOT_SUPPORTED' : res.status === 401 ? 'AI_AUTH' : 'AI_BAD_REQUEST';
    throw new ApiError(res.status === 401 ? 502 : res.status, typeof message === 'string' ? message : 'Yêu cầu AI không hợp lệ.', code);
  }
  return data;
}

module.exports = {
  enabled,
  AiUnavailableError,
  health: () => request('/health', { method: 'GET' }),
  categorize: (body, o) => request('/v1/categorize', { body, ...o }),
  parse: (body, o) => request('/v1/parse', { body, ...o }),
  forecast: (snapshot, o) => request('/v1/forecast', { body: { snapshot }, ...o }),
  anomalies: (snapshot, o) => request('/v1/anomalies', { body: { snapshot }, ...o }),
  recommendBudgets: (body, o) => request('/v1/budgets/recommend', { body, ...o }),
  search: (body, o) => request('/v1/search', { body, ...o }),
  chat: (body, o) => request('/v1/chat', { body, ...o }),
  receiptText: (body, o) => request('/v1/receipts/parse-text', { body, ...o }),
  receiptScan: (form, o) => request('/v1/receipts/scan', { form, ...o }),
};
