// Kiểm thử kết nối ngân hàng: liên kết ví, yêu cầu nhận tiền VietQR, webhook SePay.
process.env.NODE_ENV = 'test';
process.env.AUTH_RATE_LIMIT = '1000';
process.env.AI_PROVIDER = '';
process.env.AI_SERVICE_URL = '';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { connectTestDb, disconnectTestDb } = require('./helpers/db');
const { signup } = require('./helpers/auth');
const app = require('../src/app');

let token; let apiKey;
const auth = (r) => r.set('Authorization', `Bearer ${token}`);
const hook = (body, key = apiKey) => request(app).post('/api/bank/sepay/webhook')
  .set('Authorization', `Apikey ${key}`).send(body);
let seq = 1000;
const sepay = (extra) => ({
  id: (seq += 1), gateway: 'MBBank', transactionDate: '2026-11-02 10:15:00', accountNumber: '0123456789',
  subAccount: null, code: null, content: '', transferType: 'in', description: '', transferAmount: 0,
  accumulated: 0, referenceCode: 'FT1', ...extra,
});

before(async () => {
  await connectTestDb('finance_app_test_bank');
  token = (await signup(app, 'Ngân Hàng', 'bank@test.vn', 'Matkhau1')).token;
});
after(async () => {
  await disconnectTestDb();
});

test('Liên kết ngân hàng với ví: ràng buộc dữ liệu', async () => {
  const put = (body) => auth(request(app).put('/api/wallets/mb')).send({ name: 'MB', opening: 0, currency: 'VND', ...body });
  assert.equal((await put({ bankBin: '000000', bankAccount: '0123456789', bankHolder: 'NGUYEN AN' })).status, 400);
  assert.equal((await put({ bankBin: '970422', bankAccount: '12', bankHolder: 'NGUYEN AN' })).status, 400);
  assert.equal((await put({ bankBin: '970422', bankAccount: '0123456789', bankHolder: 'Nguyễn An' })).status, 400);
  assert.equal((await put({ bankBin: '970422', bankAccount: '0123456789' })).status, 400, 'thiếu tên chủ tài khoản');
  assert.equal((await put({ currency: 'USD', bankBin: '970422', bankAccount: '0123456789', bankHolder: 'NGUYEN AN' })).status, 400);
  const r = await put({ bankBin: '970422', bankAccount: '0123 456 789', bankHolder: ' nguyen  an ' });
  assert.equal(r.status, 201);
  assert.equal(r.body.bankAccount, '0123456789');
  assert.equal(r.body.bankHolder, 'NGUYEN AN');
  const banks = await request(app).get('/api/bank/banks');
  assert.ok(banks.body.items.some((b) => b.bin === '970422'));
});

test('Tạo yêu cầu nhận tiền: ràng buộc', async () => {
  const post = (body) => auth(request(app).post('/api/bank/requests')).send(body);
  assert.equal((await post({ walletId: 'cash', amount: 1000 })).status, 400, 'ví chưa liên kết ngân hàng');
  assert.equal((await post({ walletId: 'mb', amount: -5 })).status, 400);
  assert.equal((await post({ walletId: 'mb', amount: 10.5 })).status, 400);
  assert.equal((await post({ walletId: 'mb', kind: 'collect', personId: 'self', amount: 1000 })).status, 400, 'không có nợ');
  const r = await post({ walletId: 'mb', note: 'Bán đồ cũ' });
  assert.equal(r.status, 201);
  assert.match(r.body.code, /^LTD[A-Z2-9]{6}$/);
  assert.equal(r.body.amount, null);
  assert.equal(r.body.status, 'pending');
});

test('Webhook SePay: xác thực, chống trùng, khớp mã → ghi giao dịch', async () => {
  assert.equal((await hook(sepay({}), 'chua-co-khoa')).status, 401);
  const k = await auth(request(app).post('/api/bank/sepay/key'));
  assert.equal(k.status, 201);
  apiKey = k.body.apiKey;
  assert.match(k.body.webhookUrl, /\/api\/bank\/sepay\/webhook$/);
  const cfg = await auth(request(app).get('/api/bank/sepay'));
  assert.equal(cfg.body.connected, true);
  assert.equal(JSON.stringify(cfg.body).includes(apiKey), false, 'không trả lại khóa');

  const req1 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 150000, note: 'Tiền điện' })).body;
  // Tiền ra và tiền vào không có mã: bỏ qua / không khớp
  assert.equal((await hook(sepay({ transferType: 'out', transferAmount: 5000, content: req1.code }))).body.result, 'ignored');
  assert.equal((await hook(sepay({ transferAmount: 5000, content: 'chuyen tien' }))).body.result, 'unmatched');
  // Sai số tài khoản: không khớp
  assert.equal((await hook(sepay({ accountNumber: '999999', transferAmount: 150000, content: req1.code }))).body.result, 'unmatched');
  // Ngân hàng chèn khoảng trắng vào nội dung vẫn khớp được
  const spaced = `MBVCB.123 ${req1.code.slice(0, 4)} ${req1.code.slice(4)} tien dien`;
  const payload = sepay({ transferAmount: 150000, content: spaced, description: `NGUYEN VAN B ${spaced}` });
  const r = await hook(payload);
  assert.equal(r.status, 200);
  assert.equal(r.body.success, true);
  assert.equal(r.body.result, 'matched');
  const dup = await hook(payload);
  assert.equal(dup.body.duplicate, true, 'SePay gửi lại không ghi trùng');

  const paid = (await auth(request(app).get(`/api/bank/requests/${req1.id}`))).body;
  assert.equal(paid.status, 'paid');
  assert.equal(paid.paidAmount, 150000);
  const tx = (await auth(request(app).get('/api/transactions?walletId=mb'))).body.items;
  assert.equal(tx.length, 1);
  assert.equal(tx[0].kind, 'income');
  assert.equal(tx[0].categoryId, 'other_income');
  assert.equal((await auth(request(app).get('/api/wallets/mb'))).body.balance, 150000);
  // Mã đã thanh toán không ghi thêm lần nữa
  assert.equal((await hook(sepay({ transferAmount: 150000, content: req1.code }))).body.result, 'unmatched');
  assert.equal((await auth(request(app).delete(`/api/bank/requests/${req1.id}`))).status, 400);
});

test('Thu nợ qua VietQR; trả dư thì ghi thành thu nhập; hủy yêu cầu', async () => {
  await auth(request(app).post('/api/people')).send({ id: 'lan', name: 'Lan' });
  await auth(request(app).post('/api/transactions')).send({ id: 'l1', kind: 'lend', amount: 200000, walletId: 'mb', personId: 'lan', date: '2026-10-01' });
  const post = (body) => auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', kind: 'collect', personId: 'lan', ...body });
  assert.equal((await post({ amount: 300000 })).status, 400, 'vượt số còn nợ');
  assert.equal((await post({})).status, 400, 'thu nợ phải có số tiền');
  const req2 = (await post({ amount: 200000 })).body;
  assert.equal((await hook(sepay({ transferAmount: 200000, content: `${req2.code} tra no` }))).body.result, 'matched');
  let tx = (await auth(request(app).get('/api/transactions?personId=lan'))).body.items;
  assert.ok(tx.some((e) => e.kind === 'collect' && e.amount === 200000));

  // Hết nợ nhưng yêu cầu khác vẫn chờ → tiền về được ghi thành thu nhập
  await auth(request(app).post('/api/transactions')).send({ id: 'l2', kind: 'lend', amount: 50000, walletId: 'mb', personId: 'lan', date: '2026-10-02' });
  const req3 = (await post({ amount: 50000 })).body;
  await auth(request(app).post('/api/transactions')).send({ id: 'c2', kind: 'collect', amount: 50000, walletId: 'mb', personId: 'lan', date: '2026-10-03' });
  const r = await hook(sepay({ transferAmount: 50000, content: req3.code }));
  assert.equal(r.body.result, 'matched');
  tx = (await auth(request(app).get('/api/transactions?personId=lan'))).body.items;
  assert.ok(tx.some((e) => e.id === r.body.entryId && e.kind === 'income'));

  const req4 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 1000 })).body;
  assert.equal((await auth(request(app).delete(`/api/bank/requests/${req4.id}`))).body.status, 'cancelled');
  assert.equal((await hook(sepay({ transferAmount: 1000, content: req4.code }))).body.result, 'unmatched');
  const list = (await auth(request(app).get('/api/bank/requests'))).body.items;
  assert.ok(list.length >= 4);
  // Thu hồi khóa → webhook bị từ chối
  assert.equal((await auth(request(app).delete('/api/bank/sepay/key'))).status, 204);
  assert.equal((await hook(sepay({ transferAmount: 1 }))).status, 401);
});
