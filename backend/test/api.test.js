process.env.NODE_ENV = 'test';
process.env.AUTH_RATE_LIMIT = '1000';
process.env.AI_PROVIDER = '';
process.env.AI_SERVICE_URL = '';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { connectTestDb, disconnectTestDb } = require('./helpers/db');
const app = require('../src/app');
const config = require('../src/config');
const { signup, login } = require('./helpers/auth');
const { ensureSingleSessionPerUser } = require('../src/repositories/session.repository');

let token;
const api = () => request(app);
const auth = (r) => r.set('Authorization', `Bearer ${token}`);

before(async () => {
  await connectTestDb('finance_app_test');
  await ensureSingleSessionPerUser();
});
after(async () => {
  await disconnectTestDb();
});

test('Ràng buộc dữ liệu khi đăng ký', async () => {
  const reg = (body) =>
    api()
      .post('/api/auth/register')
      .send({ name: 'Nguyễn An', email: 'x@test.vn', password: 'Matkhau1', ...body });
  const cases = [
    [{ name: '' }, 'Vui lòng nhập họ tên'],
    [{ name: 'A' }, 'ít nhất 2'],
    [{ name: 'a'.repeat(51) }, 'tối đa 50'],
    [{ name: 'An123' }, 'chữ cái'],
    [{ email: '' }, 'nhập email'],
    [{ email: 'sai' }, 'không hợp lệ'],
    [{ email: 'a..b@test.vn' }, 'không hợp lệ'],
    [{ email: `${'a'.repeat(65)}@test.vn` }, 'quá dài'],
    [{ password: 'Ab1' }, 'ít nhất 8'],
    [{ password: 'abcdefgh' }, 'chữ cái và chữ số'],
    [{ password: '12345678' }, 'chữ cái và chữ số'],
    [{ password: 'Mat khau1' }, 'khoảng trắng'],
    [{ password: `A1${'a'.repeat(71)}` }, 'tối đa 72'],
    [{ password: `A1${'é'.repeat(36)}` }, '72 byte'],
    [{ email: 'abc12345@x.vn', password: 'abc12345@x.vn' }, 'trùng email'],
  ];
  for (const [body, msg] of cases) {
    const r = await reg(body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.match(r.body.error.message, new RegExp(msg), JSON.stringify(body));
  }
});

test('Đăng ký xác minh qua liên kết, đăng nhập trực tiếp, bảo vệ API', async () => {
  let r = await api()
    .post('/api/auth/register')
    .send({ name: '  Nguyễn   An ', email: 'an@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 201);
  assert.equal(r.headers['cache-control'], 'no-store');
  assert.equal(r.body.token, undefined, 'đăng ký không tự đăng nhập');
  const emailActionLink = new URL(r.body.devLink);
  assert.equal(emailActionLink.pathname, '/api/auth/open-app/verify-email');
  assert.equal(new URL(r.body.devAppLink).protocol, 'financeapp:');
  const firstToken = emailActionLink.searchParams.get('token');
  r = await api().get(emailActionLink.pathname + emailActionLink.search);
  assert.equal(r.status, 200);
  assert.match(r.text, /window\.location\.replace/);
  assert.match(r.text, /financeapp:\/\/auth\/verify-email/);
  assert.equal((await api().get(`/api/auth/verify-email?token=${firstToken}`)).status, 200);
  assert.equal((await api().get(`/api/auth/verify-email?token=${firstToken}`)).status, 200);
  assert.equal(
    (await api().post('/api/auth/login').send({ email: 'an@test.vn', password: 'Matkhau1' })).status,
    403,
    'email chưa xác minh',
  );
  r = await api().post('/api/auth/resend-verification').send({ email: 'an@test.vn' });
  assert.equal(r.status, 200);
  const verificationToken = new URL(r.body.devLink).searchParams.get('token');
  assert.equal((await api().post('/api/auth/verify-email').send({ token: firstToken })).status, 400);
  r = await api().post('/api/auth/verify-email').send({ token: verificationToken });
  assert.equal(r.status, 200);
  assert.equal(r.body.user.emailVerified, true);
  assert.equal(
    (await api().post('/api/auth/verify-email').send({ token: verificationToken })).status,
    400,
    'liên kết chỉ dùng một lần',
  );
  r = await api().post('/api/auth/register').send({ name: 'An', email: 'AN@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 409);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: 'sai-mat-khau' });
  assert.equal(r.status, 401);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: '' });
  assert.equal(r.status, 400);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 200);
  assert.ok(r.body.token, 'đăng nhập đúng mật khẩu tạo phiên');
  token = r.body.token;
  r = await api().get('/api/wallets');
  assert.equal(r.status, 401);
  r = await auth(api().get('/api/wallets'));
  assert.equal(r.status, 200);
  assert.equal(r.body.items[0].id, 'cash');
  r = await auth(api().get('/api/categories?income=false'));
  assert.equal(r.body.items.length, 7);
});

test('JWT chỉ chấp nhận thuật toán HS256', async () => {
  const jwt = require('jsonwebtoken');
  const forged = jwt.sign({ sub: '000000000000000000000000' }, config.jwtSecret, { algorithm: 'HS384' });
  const r = await api().get('/api/auth/me').set('Authorization', `Bearer ${forged}`);
  assert.equal(r.status, 401);
});

test('Ví: thêm, trùng tên, sửa, số dư tính từ giao dịch, xóa có ràng buộc', async () => {
  let r = await auth(api().post('/api/wallets')).send({
    id: 'bank',
    name: 'Ngân hàng',
    opening: 1000000,
    currency: 'VND',
  });
  assert.equal(r.status, 201);
  assert.equal(r.body.balance, 1000000);
  r = await auth(api().post('/api/wallets')).send({ name: 'ngân hàng', opening: 0 });
  assert.equal(r.status, 409);
  r = await auth(api().post('/api/wallets')).send({ name: '', opening: 0 });
  assert.equal(r.status, 400);
  r = await auth(api().post('/api/wallets')).send({
    id: 'save',
    name: 'Heo đất',
    savings: true,
    target: 5000000,
    startDate: '2026-10-01',
    deadline: '2026-09-01',
  });
  assert.equal(r.status, 400, 'ngày kết thúc trước ngày bắt đầu');
  r = await auth(api().put('/api/wallets/save')).send({
    name: 'Heo đất',
    savings: true,
    target: 5000000,
    startDate: '2026-10-01',
    deadline: '2027-10-01',
    symbol: 5,
    notify: true,
  });
  assert.equal(r.body.symbol, 5);
  assert.equal(r.body.notify, true);
  const badSymbol = await auth(api().put('/api/wallets/save')).send({ name: 'Heo đất', savings: true, symbol: 99 });
  assert.equal(badSymbol.status, 400);
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({
    id: 't1',
    kind: 'expense',
    amount: 50000,
    walletId: 'bank',
    categoryId: 'food',
    date: '2026-10-05T08:00:00Z',
  });
  assert.equal(r.status, 201);
  r = await auth(api().get('/api/wallets/bank'));
  assert.equal(r.body.balance, 950000);
  r = await auth(api().put('/api/wallets/bank')).send({ name: 'Ngân hàng', opening: 1000000, currency: 'USD' });
  assert.equal(r.status, 409, 'không đổi tiền tệ khi đã có giao dịch');
  r = await auth(api().delete('/api/wallets/bank'));
  assert.equal(r.status, 409);
  r = await auth(api().delete('/api/wallets/save'));
  assert.equal(r.status, 204);
});

test('Giao dịch: sửa, chuyển tiền, vay nợ, lọc và sắp xếp', async () => {
  let r = await auth(api().put('/api/transactions/t1')).send({
    kind: 'expense',
    amount: 80000,
    walletId: 'cash',
    categoryId: 'food',
    date: '2026-10-05T08:00:00Z',
  });
  assert.equal(r.status, 200);
  r = await auth(api().get('/api/wallets'));
  const bal = Object.fromEntries(r.body.items.map((w) => [w.id, w.balance]));
  assert.equal(bal.bank, 1000000);
  assert.equal(bal.cash, -80000);
  r = await auth(api().post('/api/transactions')).send({
    kind: 'expense',
    amount: 10,
    walletId: 'cash',
    categoryId: 'salary',
    date: '2026-10-05',
  });
  assert.equal(r.status, 400, 'danh mục thu cho khoản chi');
  r = await auth(api().post('/api/transactions')).send({
    kind: 'expense',
    amount: 0,
    walletId: 'cash',
    categoryId: 'food',
    date: '2026-10-05',
  });
  assert.equal(r.status, 400);
  r = await auth(api().post('/api/transactions')).send({
    id: 'tr',
    kind: 'transfer',
    amount: 200000,
    walletId: 'bank',
    destinationId: 'cash',
    date: '2026-10-06',
  });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({
    kind: 'transfer',
    amount: 800001,
    walletId: 'bank',
    destinationId: 'cash',
    date: '2026-10-06',
  });
  assert.equal(r.status, 400, 'chuyển vượt số dư ví nguồn');
  assert.match(r.body.error.message, /Số dư ví Ngân hàng không đủ \(còn 800\.000 VND\)/);
  r = await auth(api().put('/api/transactions/tr')).send({
    kind: 'transfer',
    amount: 1000001,
    walletId: 'bank',
    destinationId: 'cash',
    date: '2026-10-06',
  });
  assert.equal(r.status, 400, 'sửa chuyển tiền vượt số dư');
  r = await auth(api().put('/api/transactions/tr')).send({
    kind: 'transfer',
    amount: 1000000,
    walletId: 'bank',
    destinationId: 'cash',
    date: '2026-10-06',
  });
  assert.equal(r.status, 200, 'sửa trong số dư, tính lại phần giao dịch cũ');
  r = await auth(api().put('/api/transactions/tr')).send({
    kind: 'transfer',
    amount: 200000,
    walletId: 'bank',
    destinationId: 'cash',
    date: '2026-10-06',
  });
  assert.equal(r.status, 200);
  r = await auth(api().post('/api/people')).send({ id: 'binh', name: 'Bình', group: 'Bạn bè & Đồng nghiệp' });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({
    kind: 'lend',
    amount: 100000,
    walletId: 'bank',
    date: '2026-10-07',
  });
  assert.equal(r.status, 400, 'vay nợ bắt buộc đối tượng');
  r = await auth(api().post('/api/transactions')).send({
    id: 'l1',
    kind: 'lend',
    amount: 100000,
    walletId: 'bank',
    personId: 'binh',
    date: '2026-10-07',
    dueDate: '2026-10-01',
  });
  assert.equal(r.status, 400, 'hạn trước ngày giao dịch');
  r = await auth(api().post('/api/transactions')).send({
    id: 'l1',
    kind: 'lend',
    amount: 100000,
    walletId: 'bank',
    personId: 'binh',
    date: '2026-10-07',
    dueDate: '2026-11-01',
  });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({
    kind: 'collect',
    amount: 150000,
    walletId: 'bank',
    personId: 'binh',
    date: '2026-10-08',
  });
  assert.equal(r.status, 400, 'thu nợ vượt số còn lại');
  r = await auth(api().post('/api/transactions')).send({
    id: 'c1',
    kind: 'collect',
    amount: 40000,
    walletId: 'bank',
    personId: 'binh',
    date: '2026-10-08',
  });
  assert.equal(r.status, 201);
  r = await auth(api().get('/api/reports/debts'));
  assert.equal(r.body.people[0].receivable, 60000);
  r = await auth(api().get('/api/transactions?type=debt&sort=amount&order=desc'));
  assert.deepEqual(
    r.body.items.map((e) => e.id),
    ['l1', 'c1'],
  );
  r = await auth(api().get('/api/transactions?q=Bình'));
  assert.equal(r.body.total, 2);
  r = await auth(api().get('/api/transactions?from=2026-10-06&to=2026-10-06T23:59:59'));
  assert.deepEqual(
    r.body.items.map((e) => e.id),
    ['tr'],
  );
  r = await auth(api().delete('/api/people/binh'));
  assert.equal(r.status, 409);
});

test('Danh mục, ngân sách và báo cáo', async () => {
  let r = await auth(api().post('/api/categories')).send({ id: 'coffee', name: 'Cà phê', income: false, symbol: 15 });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/categories')).send({ name: 'cà phê', income: false });
  assert.equal(r.status, 409);
  r = await auth(api().post('/api/budgets')).send({
    id: 'b1',
    categoryId: 'food',
    month: '2026-10-01',
    amount: 200000,
    currency: 'VND',
  });
  assert.equal(r.status, 201);
  assert.equal(r.body.used, 80000);
  r = await auth(api().post('/api/budgets')).send({
    categoryId: 'food',
    walletId: 'cash',
    month: '2026-10-15',
    amount: 100000,
    currency: 'VND',
  });
  assert.equal(r.status, 409, 'ngân sách chồng lấn');
  r = await auth(api().post('/api/budgets')).send({
    id: 'total',
    categoryId: null,
    month: '2026-10-01',
    amount: 3000000,
    currency: 'VND',
  });
  assert.equal(r.status, 201, 'mục tiêu tổng tháng');
  r = await auth(api().delete('/api/categories/food'));
  assert.equal(r.status, 409);
  r = await auth(api().delete('/api/categories/coffee'));
  assert.equal(r.status, 204);
  r = await auth(api().get('/api/reports/dashboard?month=2026-10-01'));
  assert.equal(r.body.expense, 80000);
  assert.equal(r.body.totalBalance, 1000000 - 80000 - 100000 + 40000);
  assert.equal(r.body.budgets.length, 2);
  r = await auth(api().get('/api/reports/summary?from=2026-10-01&to=2026-10-31T23:59:59'));
  assert.equal(r.body.series[0].expense, 80000);
});

test('Đồng bộ hàng loạt và ảnh chụp dữ liệu', async () => {
  let r = await auth(api().post('/api/sync/batch')).send({
    ops: [
      { entity: 'wallets', action: 'upsert', id: 'momo', data: { name: 'Ví điện tử', opening: 300000 } },
      {
        entity: 'entries',
        action: 'upsert',
        id: 'm1',
        data: { kind: 'income', amount: 1000, walletId: 'momo', categoryId: 'bonus', date: '2026-10-09' },
      },
      { entity: 'entries', action: 'delete', id: 'khong-ton-tai' },
      {
        entity: 'entries',
        action: 'upsert',
        id: 'bad',
        data: { kind: 'income', amount: -1, walletId: 'momo', categoryId: 'bonus', date: '2026-10-09' },
      },
    ],
  });
  assert.equal(r.status, 400);
  assert.equal(r.body.applied, 3);
  assert.equal(r.body.failedIndex, 3);
  r = await auth(api().get('/api/sync'));
  assert.ok(r.body.wallets.some((w) => w.id === 'momo'));
  assert.ok(r.body.entries.some((e) => e.id === 'm1'));
  r = await auth(api().delete('/api/wallets/momo?cascade=true'));
  assert.equal(r.status, 204);
});

test('Đổi mật khẩu, quên mật khẩu, đăng xuất thu hồi token', async () => {
  let r = await auth(api().put('/api/auth/change-password')).send({ oldPassword: 'sai', newPassword: 'Abcdef12' });
  assert.equal(r.status, 400);
  r = await auth(api().put('/api/auth/change-password')).send({ oldPassword: 'Matkhau1', newPassword: 'abcdef' });
  assert.equal(r.status, 400, 'mật khẩu mới yếu');
  const oldToken = token;
  r = await auth(api().put('/api/auth/change-password')).send({ oldPassword: 'Matkhau1', newPassword: 'Abcdef12' });
  assert.equal(r.status, 200);
  token = r.body.token;
  r = await api().get('/api/auth/me').set('Authorization', `Bearer ${oldToken}`);
  assert.equal(r.status, 401, 'token cũ bị thu hồi');
  r = await api().post('/api/auth/forgot-password').send({ email: 'an@test.vn' });
  assert.equal(r.status, 200);
  assert.equal(r.body.registered, true);
  assert.equal(r.body.verified, true);
  const resetToken = new URL(r.body.devLink).searchParams.get('token');
  r = await api().post('/api/auth/reset-password/validate').send({ token: resetToken });
  assert.equal(r.status, 200);
  assert.equal(r.body.valid, true);
  assert.equal(
    (
      await api()
        .post('/api/auth/reset-password/validate')
        .send({ token: 'x'.repeat(43) })
    ).status,
    400,
  );
  r = await api().get(`/api/auth/reset-password?token=${resetToken}`);
  assert.equal(r.status, 200);
  assert.match(r.text, /name="newPassword"/);
  assert.match(r.text, /name="confirmPassword"/);
  r = await api().get(`/api/auth/reset-password?token=${'x'.repeat(43)}`);
  assert.equal(r.status, 400);
  assert.match(r.headers['content-type'], /text\/html/);
  assert.match(r.text, /không hợp lệ hoặc đã hết hạn/);
  r = await api()
    .post('/api/auth/reset-password')
    .send({ token: 'x'.repeat(43), newPassword: 'Moi12345' });
  assert.equal(r.status, 400);
  r = await api().post('/api/auth/reset-password').send({ token: resetToken, newPassword: 'moi123' });
  assert.equal(r.status, 400, 'mật khẩu mới yếu');
  r = await api().post('/api/auth/reset-password').type('form').send({
    token: resetToken,
    newPassword: 'Moi12345',
    confirmPassword: 'Moi12345',
  });
  assert.equal(r.status, 200);
  assert.match(r.headers['content-type'], /text\/html/);
  assert.equal(
    (await api().post('/api/auth/reset-password').send({ token: resetToken, newPassword: 'Khac12345' })).status,
    400,
  );
  assert.equal((await api().get('/api/auth/me').set('Authorization', `Bearer ${token}`)).status, 401);
  token = (await login(app, 'an@test.vn', 'Moi12345')).token;
  const unknownEmail = await api().post('/api/auth/forgot-password').send({ email: 'chua-dang-ky@test.vn' });
  assert.equal(unknownEmail.status, 200);
  assert.equal(unknownEmail.body.registered, false);
  assert.equal(unknownEmail.body.verified, false);
  assert.equal(unknownEmail.body.message, 'Email này chưa được đăng ký.');
  assert.equal(unknownEmail.body.devLink, undefined, 'không gửi link cho email chưa đăng ký');

  r = await auth(api().put('/api/auth/me')).send({ name: 'An Nguyễn', currency: 'USD' });
  assert.equal(r.body.user.currency, 'USD');
  r = await auth(api().post('/api/auth/logout'));
  assert.equal(r.status, 204);
  r = await auth(api().get('/api/auth/me'));
  assert.equal(r.status, 401);
});

test('Liên kết đặt lại mật khẩu chỉ dùng được một lần khi gửi yêu cầu đồng thời', async () => {
  await signup(app, 'Đổi mật khẩu', 'reset-race@test.vn', 'Matkhau1');
  const reset = (await api().post('/api/auth/forgot-password').send({ email: 'reset-race@test.vn' })).body;
  const resetToken = new URL(reset.devLink).searchParams.get('token');
  const results = await Promise.all(
    ['Moi12345', 'Khac12345'].map((newPassword) =>
      api().post('/api/auth/reset-password').send({ token: resetToken, newPassword }),
    ),
  );
  assert.deepEqual(results.map((response) => response.status).sort(), [200, 400]);
});

test('Dữ liệu tách biệt giữa người dùng', async () => {
  const t2 = (await signup(app, 'Bảo', 'bao@test.vn', 'Matkhau1')).token;
  const r = await api().get('/api/transactions').set('Authorization', `Bearer ${t2}`);
  assert.equal(r.body.total, 0);
  const w = await api().get('/api/wallets').set('Authorization', `Bearer ${t2}`);
  assert.equal(w.body.items.length, 1);
  assert.equal(w.body.items[0].balance, 0);
});

test('Đăng nhập mới thay thế phiên cũ; đăng xuất chỉ thu hồi phiên hiện tại', async () => {
  await signup(app, 'Đa', 'da@test.vn', 'Matkhau1');
  const a = await login(app, 'da@test.vn', 'Matkhau1');
  const b = await login(app, 'da@test.vn', 'Matkhau1');
  const me = (t) => api().get('/api/auth/me').set('Authorization', `Bearer ${t}`);
  assert.equal((await me(a.token)).status, 401, 'phiên cũ bị thay thế');
  assert.equal((await me(b.token)).status, 200, 'chỉ phiên mới còn hiệu lực');
  assert.equal((await api().post('/api/auth/logout').set('Authorization', `Bearer ${b.token}`)).status, 204);
  assert.equal((await me(b.token)).status, 401, 'phiên hiện tại đã đăng xuất');
  assert.equal((await api().post('/api/auth/refresh').send({ refreshToken: a.refreshToken })).status, 401);
  assert.equal((await api().post('/api/auth/refresh').send({ refreshToken: b.refreshToken })).status, 401);
});

test('Refresh token chỉ dùng được một lần kể cả khi gửi song song', async () => {
  await signup(app, 'Song', 'song@test.vn', 'Matkhau1');
  const a = await login(app, 'song@test.vn', 'Matkhau1');
  const refresh = () => api().post('/api/auth/refresh').send({ refreshToken: a.refreshToken });
  const results = await Promise.all([refresh(), refresh(), refresh()]);
  assert.deepEqual(results.map((r) => r.status).sort(), [200, 401, 401]);
  const won = results.find((r) => r.status === 200).body;
  assert.equal(
    (await api().get('/api/auth/me').set('Authorization', `Bearer ${a.token}`)).status,
    200,
    'access token cũ của cùng thiết bị vẫn dùng được trong lúc xoay vòng',
  );
  assert.equal((await api().post('/api/auth/refresh').send({ refreshToken: won.refreshToken })).status, 200);
});

test('Đăng xuất bằng token cũ (chưa có sid) không đăng xuất thiết bị khác', async () => {
  await signup(app, 'Cũ', 'cu@test.vn', 'Matkhau1');
  const a = await login(app, 'cu@test.vn', 'Matkhau1');
  const b = await login(app, 'cu@test.vn', 'Matkhau1');
  const { User } = require('../src/models');
  const { signAccessToken } = require('../src/services/session.service');
  const legacy = signAccessToken(await User.findOne({ email: 'cu@test.vn' }));
  const r = await api()
    .post('/api/auth/logout')
    .set('Authorization', `Bearer ${legacy}`)
    .send({ refreshToken: a.refreshToken });
  assert.equal(r.status, 204);
  assert.equal((await api().post('/api/auth/refresh').send({ refreshToken: a.refreshToken })).status, 401);
  assert.equal((await api().get('/api/auth/me').set('Authorization', `Bearer ${b.token}`)).status, 200);
});

test('Khóa đăng nhập sau nhiều lần nhập sai mật khẩu', async () => {
  await signup(app, 'Khóa', 'khoa@test.vn', 'Matkhau1');
  let r;
  for (let i = 0; i < config.maxFailedLogins; i += 1) {
    r = await api().post('/api/auth/login').send({ email: 'khoa@test.vn', password: 'SaiMatKhau9' });
    assert.equal(r.status, 401);
  }
  r = await api().post('/api/auth/login').send({ email: 'khoa@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 429);
  assert.equal(r.body.error.code, 'ACCOUNT_LOCKED');
});

test('Thông báo thời gian khóa dưới một phút bằng giây', async () => {
  await signup(app, 'Khóa ngắn', 'khoa-ngan@test.vn', 'Matkhau1');
  const { User } = require('../src/models');
  await User.updateOne({ email: 'khoa-ngan@test.vn' }, { lockUntil: new Date(Date.now() + 30000) });
  const r = await api().post('/api/auth/login').send({ email: 'khoa-ngan@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 429);
  assert.equal(r.body.error.code, 'ACCOUNT_LOCKED');
  assert.match(r.body.error.message, /Thử lại sau \d+ giây\./);
});

test('Đăng ký lại email chưa xác thực cập nhật thông tin và yêu cầu xác minh lại', async () => {
  const { User } = require('../src/models');
  const bcrypt = require('bcryptjs');
  await User.create({ name: 'Cũ', email: 'old_user@corp.com', passwordHash: await bcrypt.hash('cu123456', 10) });
  let r = await api()
    .post('/api/auth/register')
    .send({ name: 'Ke Gian', email: 'victim@test.vn', password: 'Matkhau1' });
  const firstToken = new URL(r.body.devLink).searchParams.get('token');
  await api().post('/api/auth/verify-email').send({ token: firstToken });
  await User.updateOne({ email: 'victim@test.vn' }, { emailVerified: false });
  r = await api()
    .post('/api/auth/register')
    .send({ name: 'Ke Gian', email: 'victim@test.vn', password: 'Chiemquyen9' });
  assert.equal(r.status, 201);
  assert.equal(
    (await api().post('/api/auth/login').send({ email: 'victim@test.vn', password: 'Matkhau1' })).status,
    401,
    'mật khẩu cũ được thay khi đăng ký lại',
  );
  assert.equal(
    (await api().post('/api/auth/login').send({ email: 'victim@test.vn', password: 'Chiemquyen9' })).status,
    403,
    'chưa xác minh email',
  );
  const nextToken = new URL(r.body.devLink).searchParams.get('token');
  assert.equal((await api().post('/api/auth/verify-email').send({ token: nextToken })).status, 200);
  assert.equal(
    (await api().post('/api/auth/login').send({ email: 'victim@test.vn', password: 'Chiemquyen9' })).status,
    200,
  );
  assert.equal(
    (await api().post('/api/auth/login').send({ email: 'Old_User@corp.com', password: 'cu123456' })).status,
    403,
    'tài khoản cũ chưa được xác minh cũng không đăng nhập được',
  );
});
