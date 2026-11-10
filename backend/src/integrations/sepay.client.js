const config = require('../config');

async function listTransactions(params) {
  const url = new URL(`${config.sepay.apiUrl}/transactions/list`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, value);
  }
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${config.sepay.apiToken}`, 'Content-Type': 'application/json' },
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 429) {
    throw new Error(`SePay giới hạn tần suất, thử lại sau ${res.headers.get('x-sepay-userapi-retry-after') || 1} giây`);
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.status !== 200) {
    throw new Error(`SePay trả lỗi ${res.status}: ${JSON.stringify(body.error || body.messages || '')}`);
  }
  return body.transactions || [];
}

module.exports = { listTransactions };
