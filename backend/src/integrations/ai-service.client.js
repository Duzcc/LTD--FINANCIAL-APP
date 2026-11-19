const crypto = require('node:crypto');
const config = require('../config');
const { ApiError } = require('../utils/errors');

class AiUnavailableError extends ApiError {
  constructor(message = 'Dịch vụ AI tạm thời không khả dụng.', cause) {
    super(503, message, 'AI_UNAVAILABLE');
    this.cause = cause;
  }
}

const enabled = () => Boolean(config.aiService.url);

function clientError(status, data) {
  const detail = data?.error?.message || data?.detail;
  const message = typeof detail === 'string' ? detail : 'Yêu cầu AI không hợp lệ.';
  if (status === 501) return new ApiError(501, message, 'AI_NOT_SUPPORTED');
  if (status === 401) return new ApiError(502, message, 'AI_AUTH');
  return new ApiError(status, message, 'AI_BAD_REQUEST');
}

async function request(path, { method = 'POST', body, form, requestId } = {}) {
  if (!enabled()) throw new AiUnavailableError('Chưa cấu hình AI_SERVICE_URL.');
  const headers = { 'x-request-id': requestId || crypto.randomUUID().slice(0, 12) };
  if (config.aiService.key) headers['x-api-key'] = config.aiService.key;
  let payload = form;
  if (!form && body !== undefined) {
    headers['content-type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  const res = await fetch(config.aiService.url + path, {
    method,
    headers,
    body: payload,
    signal: AbortSignal.timeout(config.aiService.timeoutMs),
  }).catch((e) => {
    throw new AiUnavailableError(undefined, e);
  });
  if (res.status >= 500 && res.status !== 501) throw new AiUnavailableError(undefined, new Error(`HTTP ${res.status}`));
  const data = await res.json().catch(() => null);
  if (!res.ok) throw clientError(res.status, data);
  return data;
}

module.exports = {
  enabled,
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
