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
const config = require('../src/config');
const sepayService = require('../src/services/sepay.service');

let token; let apiKey;
const auth = (r) => r.set('Authorization', `Bearer ${token}`);
const hook = (body, key = apiKey) => request(app).post('/api/bank/sepay/webhook')
  .set('Authorization', `Apikey ${key}`).send(body);
let seq = 1000;
const sepay_payload = (code) => ({
  id: 9001, gateway: 'MBBank', transactionDate: '2026-11-02 15:00:00', accountNumber: '0123456789', code: null,
  content: code, transferType: 'in', description: '', transferAmount: 75000, accumulated: 0, referenceCode: 'FT9',
});
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
  assert.equal((await hook(sepay({ transferType: 'out', transferAmount: 5000, content: req1.code }))).body.result, 'recorded', 'tiền ra của tài khoản đã liên kết');
  assert.equal((await hook(sepay({ transferAmount: 5000, content: 'chuyen tien' }))).body.result, 'recorded', 'tiền vào không có mã');
  assert.equal((await hook(sepay({ accountNumber: '999999', transferAmount: 150000, content: req1.code }))).body.result, 'unmatched');
  assert.equal((await hook(sepay({ accountNumber: '999999', transferType: 'out', transferAmount: 1000 }))).body.result, 'ignored');
  const spaced = `MBVCB.123 ${req1.code.slice(0, 4)} ${req1.code.slice(4)} tien dien`;
  const payload = sepay({ transferAmount: 150000, content: spaced, description: `NGUYEN VAN B ${spaced}` });
  const r = await hook(payload);
  assert.equal(r.status, 200);
  assert.equal(r.body.success, true);
  assert.equal(r.body.result, 'matched');
  const dup = await hook(payload);
  assert.equal(dup.body.result, 'duplicate', 'SePay gửi lại không ghi trùng');

  const paid = (await auth(request(app).get(`/api/bank/requests/${req1.id}`))).body;
  assert.equal(paid.status, 'paid');
  assert.equal(paid.paidAmount, 150000);
  const tx = (await auth(request(app).get('/api/transactions?walletId=mb'))).body.items;
  assert.deepEqual(tx.map((e) => [e.kind, e.amount]).sort(), [['expense', 5000], ['income', 150000], ['income', 5000]]);
  assert.equal(tx.find((e) => e.id === r.body.entryId).categoryId, 'other_income');
  assert.match(tx.find((e) => e.kind === 'expense').note, /^Chuyển khoản đi/);
  assert.equal((await auth(request(app).get('/api/wallets/mb'))).body.balance, 150000);
  assert.equal((await hook(sepay({ transferAmount: 150000, content: req1.code }))).body.result, 'recorded', 'mã đã thanh toán: vẫn là tiền vào tài khoản');
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

  await auth(request(app).post('/api/transactions')).send({ id: 'l2', kind: 'lend', amount: 50000, walletId: 'mb', personId: 'lan', date: '2026-10-02' });
  const req3 = (await post({ amount: 50000 })).body;
  await auth(request(app).post('/api/transactions')).send({ id: 'c2', kind: 'collect', amount: 50000, walletId: 'mb', personId: 'lan', date: '2026-10-03' });
  const r = await hook(sepay({ transferAmount: 50000, content: req3.code }));
  assert.equal(r.body.result, 'matched');
  tx = (await auth(request(app).get('/api/transactions?personId=lan'))).body.items;
  assert.ok(tx.some((e) => e.id === r.body.entryId && e.kind === 'income'));

  const req4 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 1000 })).body;
  assert.equal((await auth(request(app).delete(`/api/bank/requests/${req4.id}`))).body.status, 'cancelled');
  assert.equal((await hook(sepay({ transferAmount: 1000, content: req4.code }))).body.result, 'recorded');
  const list = (await auth(request(app).get('/api/bank/requests'))).body.items;
  assert.ok(list.length >= 4);
  assert.equal((await auth(request(app).delete('/api/bank/sepay/key'))).status, 204);
  assert.equal((await hook(sepay({ transferAmount: 1 }))).status, 401);
});

test('Giao dịch ngân hàng trùng khoản đã ghi tay thì gộp, không ghi hai lần', async () => {
  apiKey = (await auth(request(app).post('/api/bank/sepay/key'))).body.apiKey;
  await auth(request(app).post('/api/wallets')).send({ id: 'tm', name: 'Ví tay', opening: 100000 });
  await auth(request(app).post('/api/transactions')).send({ id: 'hand', kind: 'expense', amount: 42000, walletId: 'mb', categoryId: 'food', date: '2026-11-02T09:00:00+07:00', note: 'Ăn trưa' });
  await auth(request(app).post('/api/transactions')).send({ id: 'move', kind: 'transfer', amount: 64000, walletId: 'tm', destinationId: 'mb', date: '2026-11-02T08:00:00+07:00' });
  const before = (await auth(request(app).get('/api/transactions?walletId=mb'))).body.items.length;
  let r = await hook(sepay({ transferType: 'out', transferAmount: 42000, content: 'QR thanh toan' }));
  assert.deepEqual(r.body, { success: true, result: 'linked', entryId: 'hand' });
  r = await hook(sepay({ transferAmount: 64000, content: 'nap tien' }));
  assert.equal(r.body.entryId, 'move', 'khoản chuyển vào ví đã ghi tay');
  r = await hook(sepay({ transferType: 'out', transferAmount: 42000, content: 'lan hai' }));
  assert.equal(r.body.result, 'recorded', 'khoản ghi tay chỉ gộp với một giao dịch ngân hàng');
  r = await hook(sepay({ transferType: 'out', transferAmount: 42000, transactionDate: '2026-11-09 10:00:00' }));
  assert.equal(r.body.result, 'recorded');
  const after = (await auth(request(app).get('/api/transactions?walletId=mb'))).body.items;
  assert.equal(after.length, before + 2);
  assert.equal(after.find((e) => e.id === 'hand').note, 'Ăn trưa', 'giữ nguyên khoản ghi tay');
});

test('Đối soát qua SePay User API (không cần webhook): khớp mã, chống trùng với webhook', async () => {
  const calls = [];
  let rows = [];
  const realFetch = global.fetch;
  global.fetch = async (url, opts) => {
    calls.push({ url: String(url), auth: opts.headers.Authorization });
    return new Response(JSON.stringify({ status: 200, error: null, messages: { success: true }, transactions: rows }), { status: 200 });
  };
  config.sepay.apiToken = 'token-thu';
  config.sepay.minGapMs = 0;
  sepayService.resetCursor();
  try {
    await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 1 })
      .then((r) => auth(request(app).delete(`/api/bank/requests/${r.body.id}`)));
    await sepayService.syncFromApi();
    const pendingBefore = calls.length;

    const req5 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 75000, note: 'Ve xem phim' })).body;
    rows = [
      { id: '9001', transaction_date: '2026-11-02 15:00:00', account_number: '0123456789', amount_in: '75000.00', amount_out: '0.00', code: null, transaction_content: `MBVCB ${req5.code} VE XEM PHIM`, bank_brand_name: 'MBBank' },
      { id: '9002', transaction_date: '2026-11-02 15:01:00', account_number: '0123456789', amount_in: '0.00', amount_out: '20000.00', code: null, transaction_content: 'thanh toan', bank_brand_name: 'MBBank' },
      { id: '9003', transaction_date: '2026-11-02 15:02:00', account_number: '0123456789', amount_in: '30000.00', amount_out: '0.00', code: null, transaction_content: 'chuyen tien khong ma', bank_brand_name: 'MBBank' },
    ];
    const r = await auth(request(app).get(`/api/bank/requests/${req5.id}`));
    assert.equal(r.body.status, 'paid');
    assert.equal(r.body.paidAmount, 75000);
    assert.ok(calls.length > pendingBefore);
    assert.equal(calls.at(-1).auth, 'Bearer token-thu');
    assert.match(calls.at(-1).url, /userapi\/transactions\/list\?transaction_date_min=/);
    await sepayService.syncFromApi();
    assert.match(calls.at(-1).url, /since_id=9004/);
    apiKey = (await auth(request(app).post('/api/bank/sepay/key'))).body.apiKey;
    const dup = await hook(sepay_payload(req5.code));
    assert.equal(dup.body.result, 'duplicate');
    const tx = (await auth(request(app).get('/api/transactions?q=Ve xem phim'))).body.items;
    assert.equal(tx.length, 1);
    const cfg = (await auth(request(app).get('/api/bank/sepay'))).body;
    assert.equal(cfg.pollingEnabled, true);
  } finally {
    global.fetch = realFetch;
    config.sepay.apiToken = '';
    config.sepay.minGapMs = 3000;
  }
});

test('Đối soát định kỳ: chỉ chủ tài khoản SePay được ghi giao dịch không có mã, kể cả khi không có mã QR đang chờ', async () => {
  let rows = [];
  const realFetch = global.fetch;
  global.fetch = async () => new Response(JSON.stringify({ status: 200, transactions: rows }), { status: 200 });
  config.sepay.apiToken = 'token-thu';
  config.sepay.minGapMs = 0;
  const { PaymentRequest } = require('../src/models');
  await PaymentRequest.updateMany({ status: 'pending' }, { status: 'cancelled' });
  try {
    rows = [
      { id: '9101', transaction_date: '2026-11-03 09:00:00', account_number: '0123456789', amount_in: '30000.00', amount_out: '0.00', code: null, transaction_content: 'TRAN VAN A chuyen tien' },
      { id: '9102', transaction_date: '2026-11-03 09:05:00', account_number: '0123456789', amount_in: '0.00', amount_out: '12000.00', code: null, transaction_content: 'thanh toan QR' },
      { id: '9103', transaction_date: '2026-11-03 09:06:00', account_number: '5555555555', amount_in: '9000.00', amount_out: '0.00', code: null, transaction_content: 'tai khoan khac' },
    ];
    sepayService.resetCursor();
    assert.deepEqual(await sepayService.syncFromApi(), { checked: 0, matched: 0 }, 'chưa chỉ định chủ tài khoản thì không đọc');
    config.sepay.ownerEmail = 'bank@test.vn';
    assert.deepEqual(await sepayService.syncFromApi(), { checked: 3, matched: 2 });
    const tx = (await auth(request(app).get('/api/transactions?walletId=mb'))).body.items;
    assert.ok(tx.some((e) => e.id === 'bank_9101' && e.kind === 'income' && e.amount === 30000 && /TRAN VAN A/.test(e.note)));
    assert.ok(tx.some((e) => e.id === 'bank_9102' && e.kind === 'expense' && e.amount === 12000));
    sepayService.resetCursor();
    assert.deepEqual(await sepayService.syncFromApi(), { checked: 3, matched: 0 });
    assert.equal((await auth(request(app).get('/api/transactions?walletId=mb'))).body.items.length, tx.length, 'quét lại không ghi trùng');
  } finally {
    global.fetch = realFetch;
    config.sepay.apiToken = '';
    config.sepay.ownerEmail = '';
    config.sepay.minGapMs = 3000;
  }
});

test('Chuyển thiếu: ghi đúng số tiền nhận, yêu cầu chỉ xong khi đủ; mã giả "LTD…" trong nội dung không che mã thật', async () => {
  apiKey = (await auth(request(app).post('/api/bank/sepay/key'))).body.apiKey;
  const req6 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 100000, note: 'Tien hoc' })).body;
  let r = await hook(sepay({ transferAmount: 40000, content: `CONG TY ABC LTD CHUYEN TIEN ${req6.code}` }));
  assert.equal(r.body.result, 'matched');
  let st = (await auth(request(app).get(`/api/bank/requests/${req6.id}`))).body;
  assert.equal(st.status, 'pending', 'mới nhận 40.000/100.000');
  assert.equal(st.paidAmount, 40000);
  r = await hook(sepay({ transferAmount: 60000, content: req6.code }));
  assert.equal(r.body.result, 'matched');
  st = (await auth(request(app).get(`/api/bank/requests/${req6.id}`))).body;
  assert.equal(st.status, 'paid');
  assert.equal(st.paidAmount, 100000);
  const tx = (await auth(request(app).get('/api/transactions?q=Tien hoc'))).body.items;
  assert.equal(tx.length, 2, 'cả hai lần chuyển đều được ghi');
});

test('Ghi giao dịch lỗi thì SePay gửi lại vẫn xử lý được (không bị coi là trùng)', async () => {
  const { Category, User } = require('../src/models');
  const user = await User.findOne({ email: 'bank@test.vn' });
  const req7 = (await auth(request(app).post('/api/bank/requests')).send({ walletId: 'mb', amount: 5000 })).body;
  const payload = sepay({ transferAmount: 5000, content: req7.code });
  const incomes = await Category.find({ user: user._id, income: true }).lean();
  await Category.deleteMany({ user: user._id, income: true });
  assert.equal((await hook(payload)).status, 400, 'không có danh mục thu nhập để ghi');
  await Category.insertMany(incomes);
  const r = await hook(payload);
  assert.equal(r.body.result, 'matched', 'lần gửi lại ghi được');
  assert.equal((await auth(request(app).get(`/api/bank/requests/${req7.id}`))).body.status, 'paid');
});
