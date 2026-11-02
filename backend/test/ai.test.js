// Kiểm thử tích hợp backend ↔ AI service bằng một AI service giả lập (stub),
// và (tùy chọn) với AI service thật khi đặt E2E_AI_URL=http://localhost:8000.
process.env.NODE_ENV = 'test';
process.env.AUTH_RATE_LIMIT = '1000';
// Không để tệp .env của máy phát triển ảnh hưởng kết quả kiểm thử.
process.env.AI_PROVIDER = '';
process.env.AI_RATE_LIMIT = '1000';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

const calls = [];
let stub;
let mode = 'ok';

function startStub() {
  const s = express();
  s.use(express.json({ limit: '20mb' }));
  s.use((req, res, next) => {
    calls.push({ path: req.path, key: req.get('x-api-key'), body: req.body, type: req.get('content-type') });
    if (mode === 'down' && req.path !== '/health') return res.status(503).json({ detail: 'down' });
    next();
  });
  s.get('/health', (_q, r) => r.json({ status: mode === 'down' ? 'down' : 'ok', version: '1.0.0', assistant: 'rules' }));
  s.post('/v1/chat', (q, r) => r.json({ reply: `Có ${q.body.snapshot.transactions.length} giao dịch`, provider: 'rules', toolsUsed: ['get_overview'], actions: [{ type: 'create_transaction', data: { amount: 1 } }] }));
  s.post('/v1/categorize', (q, r) => r.json({ predictions: [{ categoryId: q.body.categories[0].id, probability: 0.9 }], personalWeight: q.body.history.length ? 0.5 : 0, modelVersion: 't' }));
  s.post('/v1/parse', (q, r) => r.json({ kind: 'expense', amount: 45000, note: q.body.text }));
  s.post('/v1/forecast', (q, r) => r.json({ projected: 123, now: q.body.snapshot.now }));
  s.post('/v1/anomalies', (_q, r) => r.status(500).json({}));
  s.post('/v1/budgets/recommend', (q, r) => r.json({ suggestions: [], savingsRate: q.body.savingsRate }));
  s.post('/v1/search', (q, r) => r.json({ filters: {}, hits: [], query: q.body.query }));
  s.post('/v1/receipts/parse-text', (_q, r) => r.json({ total: 46000 }));
  s.post('/v1/receipts/scan', (_q, r) => r.status(501).json({ detail: 'Máy chủ chưa có mô hình thị giác' }));
  return new Promise((resolve) => { const srv = http.createServer(s).listen(0, () => resolve(srv)); });
}

let app; let api; let token;
const request = require('supertest');
const { connectTestDb, disconnectTestDb } = require('./helpers/db');
const { signup } = require('./helpers/auth');
const auth = (r) => r.set('Authorization', `Bearer ${token}`);

before(async () => {
  stub = await startStub();
  process.env.AI_SERVICE_URL = process.env.E2E_AI_URL || `http://127.0.0.1:${stub.address().port}`;
  process.env.AI_SERVICE_KEY = process.env.E2E_AI_KEY || 'stub-key';
  app = require('../src/app');
  api = () => request(app);
  await connectTestDb('finance_app_ai_test');
  token = (await signup(app, 'Trợ Lý', 'ai@test.vn', 'Matkhau1')).token;
  const now = new Date();
  const changes = [
    { entity: 'entries', action: 'upsert', id: 'tx1', data: { kind: 'expense', amount: 45000, date: now.toISOString(), walletId: 'cash', categoryId: 'food', note: 'Phở bò' } },
    { entity: 'entries', action: 'upsert', id: 'tx2', data: { kind: 'expense', amount: 30000, date: now.toISOString(), walletId: 'cash', categoryId: 'transport', note: 'Grab đi làm' } },
  ];
  const s = await auth(api().post('/api/sync/batch')).send({ ops: changes });
  assert.equal(s.status, 200, JSON.stringify(s.body));
});
after(async () => {
  await disconnectTestDb();
  stub.close();
});

const e2e = Boolean(process.env.E2E_AI_URL);

test('status báo AI service sẵn sàng', async () => {
  const r = await auth(api().get('/api/ai/status'));
  assert.equal(r.status, 200);
  assert.equal(r.body.provider, 'ai-service');
  assert.ok(r.body.features.includes('forecast'));
});

test('chat chuyển tiếp snapshot (không lộ thông tin tài khoản) kèm khóa dịch vụ', { skip: e2e }, async () => {
  calls.length = 0;
  const r = await auth(api().post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'tháng này chi bao nhiêu' }] });
  assert.equal(r.status, 200);
  assert.equal(r.body.source, 'ai-service');
  assert.equal(r.body.reply, 'Có 2 giao dịch');
  assert.equal(r.body.actions[0].type, 'create_transaction');
  const c = calls.find((x) => x.path === '/v1/chat');
  assert.equal(c.key, 'stub-key');
  const snap = c.body.snapshot;
  assert.match(snap.now, /[+-]\d\d:\d\d$/);
  assert.ok(snap.wallets.length && snap.categories.length);
  assert.equal(snap.transactions[0].note, 'Phở bò');
  assert.ok(!JSON.stringify(c.body).includes('ai@test.vn'));
  assert.ok(!JSON.stringify(c.body).includes('password'));
});

test('categorize gửi lịch sử cá nhân hóa', { skip: e2e }, async () => {
  calls.length = 0;
  const r = await auth(api().post('/api/ai/categorize')).send({ text: 'phở', income: false });
  assert.equal(r.status, 200);
  assert.equal(r.body.personalWeight, 0.5);
  assert.equal(calls[0].body.history.length, 2);
  assert.equal((await auth(api().post('/api/ai/categorize')).send({})).status, 400);
});

test('các API phân tích và lỗi dịch vụ', { skip: e2e }, async () => {
  assert.equal((await auth(api().post('/api/ai/parse')).send({ text: 'phở 45k' })).body.amount, 45000);
  assert.equal((await auth(api().get('/api/ai/forecast'))).body.projected, 123);
  const a = await auth(api().get('/api/ai/anomalies'));
  assert.equal(a.status, 503);
  assert.equal(a.body.error.code, 'AI_UNAVAILABLE');
  const ins = await auth(api().get('/api/ai/insights'));
  assert.equal(ins.status, 200);
  assert.equal(ins.body.anomalies, null);
  assert.equal(ins.body.forecast.projected, 123);
  assert.equal((await auth(api().get('/api/ai/budgets/recommend?savingsRate=0.3'))).body.savingsRate, 0.3);
  assert.equal((await auth(api().get('/api/ai/budgets/recommend?savingsRate=2'))).status, 400);
  assert.equal((await auth(api().post('/api/ai/search')).send({ query: 'cafe' })).body.query, 'cafe');
  assert.equal((await auth(api().post('/api/ai/receipts/text')).send({ text: 'TỔNG 46.000' })).body.total, 46000);
});

test('đọc ảnh hóa đơn: chuyển multipart, 501 khi máy chủ không hỗ trợ', { skip: e2e }, async () => {
  calls.length = 0;
  const image = Buffer.from('fake-jpeg').toString('base64');
  const r = await auth(api().post('/api/ai/receipts/scan')).send({ image, mediaType: 'image/jpeg' });
  assert.equal(r.status, 501);
  assert.equal(r.body.error.code, 'AI_NOT_SUPPORTED');
  assert.match(calls[0].type, /multipart\/form-data/);
  assert.equal((await auth(api().post('/api/ai/receipts/scan')).send({ image, mediaType: 'image/gif' })).status, 400);
});

test('chat lùi về trợ lý luật khi AI service sập', { skip: e2e }, async () => {
  mode = 'down';
  const r = await auth(api().post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'tổng quan' }] });
  mode = 'ok';
  assert.equal(r.status, 200);
  assert.equal(r.body.source, 'rules');
  assert.ok(r.body.reply.length > 0);
});

test('E2E với AI service thật', { skip: !e2e }, async () => {
  const p = await auth(api().post('/api/ai/parse')).send({ text: 'ăn phở 45k sáng nay' });
  assert.equal(p.status, 200, JSON.stringify(p.body));
  assert.equal(p.body.amount, 45000);
  assert.equal(p.body.categoryId, 'food');
  const c = await auth(api().post('/api/ai/chat')).send({ messages: [{ role: 'user', content: 'ghi giúp grab 30k' }] });
  assert.equal(c.body.source, 'ai-service');
  assert.equal(c.body.actions[0].data.amount, 30000);
  for (const path of ['/api/ai/forecast', '/api/ai/anomalies', '/api/ai/budgets/recommend', '/api/ai/insights']) {
    const r = await auth(api().get(path));
    assert.equal(r.status, 200, `${path}: ${JSON.stringify(r.body)}`);
  }
  const s = await auth(api().post('/api/ai/search')).send({ query: 'phở hôm nay' });
  assert.equal(s.body.hits[0].transactionId, 'tx1');
});
