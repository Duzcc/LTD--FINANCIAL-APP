// Kiểm thử các chức năng mở rộng: refresh token, xác thực email, giao dịch định kỳ, trợ lý AI.
process.env.NODE_ENV = 'test';
process.env.AUTH_RATE_LIMIT = '1000';
// Không để tệp .env của máy phát triển ảnh hưởng kết quả kiểm thử.
process.env.AI_PROVIDER = '';
process.env.AI_SERVICE_URL = '';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { connectTestDb, disconnectTestDb } = require('./helpers/db');
const app = require('../src/app');
const config = require('../src/config');
const { signup } = require('./helpers/auth');
const { User } = require('../src/models');

let token; let refresh;
const auth = (r) => r.set('Authorization', `Bearer ${token}`);

before(async () => {
  await connectTestDb('finance_app_test_extra');
  const r = await signup(app, 'Chi', 'chi@test.vn', 'Matkhau1');
  token = r.token; refresh = r.refreshToken;
});
after(async () => {
  await disconnectTestDb();
});

test('Refresh token xoay vòng và bị thu hồi khi đăng xuất', async () => {
  assert.ok(refresh);
  let r = await request(app).post('/api/auth/refresh').send({ refreshToken: refresh });
  assert.equal(r.status, 200);
  assert.notEqual(r.body.refreshToken, refresh);
  const old = refresh;
  refresh = r.body.refreshToken; token = r.body.token;
  r = await request(app).post('/api/auth/refresh').send({ refreshToken: old });
  assert.equal(r.status, 401, 'refresh token đã dùng không dùng lại được');
  r = await request(app).post('/api/auth/refresh').send({ refreshToken: 'sai' });
  assert.equal(r.status, 401);
});

test('Xác thực email bằng mã', async () => {
  let r = await auth(request(app).get('/api/auth/me'));
  assert.equal(r.body.user.emailVerified, true, 'đã xác thực qua OTP khi đăng ký');
  // Tài khoản cũ chưa xác thực vẫn dùng được mã xác thực trong mục Tài khoản
  await User.updateOne({ email: 'chi@test.vn' }, { emailVerified: false });
  r = await auth(request(app).post('/api/auth/verify-email')).send({ code: '000000' });
  assert.equal(r.status, 400);
  r = await auth(request(app).post('/api/auth/resend-verification'));
  const code = r.body.devCode;
  r = await auth(request(app).post('/api/auth/verify-email')).send({ code });
  assert.equal(r.status, 200);
  assert.equal(r.body.user.emailVerified, true);
});

test('Giao dịch định kỳ: CRUD, ràng buộc và xóa ví kèm dữ liệu', async () => {
  let r = await auth(request(app).post('/api/recurring')).send({
    id: 'rent', kind: 'expense', amount: 3000000, walletId: 'cash', categoryId: 'house', note: 'Tiền nhà',
    frequency: 'monthly', startDate: '2026-10-05T02:00:00Z',
  });
  assert.equal(r.status, 201);
  r = await auth(request(app).post('/api/recurring')).send({ kind: 'expense', amount: 1, walletId: 'cash', categoryId: 'salary', startDate: '2026-10-05' });
  assert.equal(r.status, 400);
  r = await auth(request(app).post('/api/transactions')).send({ id: 'rent_r20261005', kind: 'expense', amount: 3000000, walletId: 'cash', categoryId: 'house', date: '2026-10-05T02:00:00Z', recurringId: 'rent' });
  assert.equal(r.status, 201);
  assert.equal(r.body.recurringId, 'rent');
  r = await auth(request(app).delete('/api/categories/house'));
  assert.equal(r.status, 409);
  r = await auth(request(app).put('/api/auth/me')).send({ rates: { USD: 25000, XXX: 1 } });
  assert.deepEqual(r.body.user.rates, { USD: 25000 });
  r = await auth(request(app).get('/api/sync'));
  assert.equal(r.body.recurring.length, 1);
  r = await auth(request(app).delete('/api/wallets/cash?cascade=true'));
  assert.equal(r.status, 204);
  r = await auth(request(app).get('/api/recurring'));
  assert.equal(r.body.items.length, 0);
});

test('Trợ lý AI: chế độ luật khi chưa cấu hình và gọi mô hình khi có cấu hình', async () => {
  let r = await auth(request(app).post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'Tháng này tôi chi bao nhiêu?' }] });
  assert.equal(r.status, 200);
  assert.equal(r.body.source, 'rules');
  r = await auth(request(app).post('/api/ai/chat')).send({ messages: [] });
  assert.equal(r.status, 400);

  const saved = { ...config.ai };
  const realFetch = global.fetch;
  let sent;
  global.fetch = async (url, opts) => {
    sent = { url, body: JSON.parse(opts.body), headers: opts.headers };
    return { ok: true, status: 200, json: async () => ({ content: [{ type: 'text', text: 'Bạn đã chi 0 ₫.' }] }) };
  };
  Object.assign(config.ai, { provider: 'anthropic', apiKey: 'test-key', model: 'claude-test' });
  try {
    r = await auth(request(app).get('/api/ai/status'));
    assert.equal(r.body.enabled, true);
    r = await auth(request(app).post('/api/ai/chat')).send({ messages: [
      { role: 'assistant', content: 'Xin chào' },
      { role: 'user', content: 'Tháng này tôi chi bao nhiêu?' },
    ] });
    assert.equal(r.body.source, 'llm');
    assert.equal(r.body.reply, 'Bạn đã chi 0 ₫.');
    assert.match(sent.url, /\/v1\/messages$/);
    assert.equal(sent.headers['x-api-key'], 'test-key');
    assert.equal(sent.body.model, 'claude-test');
    assert.equal(sent.body.messages[0].role, 'user', 'bỏ tin nhắn mở đầu của trợ lý');
    assert.match(sent.body.system, /Dữ liệu tài chính/);

    Object.assign(config.ai, { provider: 'openai', baseUrl: 'http://localhost:11434/v1', apiKey: '', model: 'llama3.1' });
    global.fetch = async (url, opts) => {
      sent = { url, body: JSON.parse(opts.body) };
      return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'Trả lời từ Ollama' } }] }) };
    };
    r = await auth(request(app).post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'Gợi ý tiết kiệm' }] });
    assert.equal(r.body.reply, 'Trả lời từ Ollama');
    assert.equal(sent.url, 'http://localhost:11434/v1/chat/completions');
    assert.equal(sent.body.messages[0].role, 'system');

    global.fetch = async () => { throw new Error('mạng lỗi'); };
    r = await auth(request(app).post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'Hỏi' }] });
    assert.equal(r.body.source, 'rules', 'lỗi mô hình thì trả lời dự phòng');
  } finally {
    global.fetch = realFetch;
    Object.assign(config.ai, saved);
  }
});

test('Gửi lại OTP: mã cũ hết hiệu lực, giới hạn số lần gửi', async () => {
  const wait = config.otp.resendSeconds;
  config.otp.resendSeconds = 0;
  try {
    const step = (await request(app).post('/api/auth/login').send({ email: 'chi@test.vn', password: 'Matkhau1' })).body;
    const again = await request(app).post('/api/auth/resend-otp').send({ otpToken: step.otpToken });
    assert.equal(again.status, 200);
    assert.match(again.body.devCode, /^\d{6}$/);
    if (again.body.devCode !== step.devCode) {
      const old = await request(app).post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: step.devCode });
      assert.equal(old.status, 400, 'mã cũ không dùng được nữa');
    }
    for (let i = 2; i < config.otp.maxSends; i += 1) {
      assert.equal((await request(app).post('/api/auth/resend-otp').send({ otpToken: step.otpToken })).status, 200);
    }
    const r = await request(app).post('/api/auth/resend-otp').send({ otpToken: step.otpToken });
    assert.equal(r.status, 429);
    assert.equal(r.body.error.code, 'OTP_EXPIRED');
  } finally {
    config.otp.resendSeconds = wait;
  }
});
