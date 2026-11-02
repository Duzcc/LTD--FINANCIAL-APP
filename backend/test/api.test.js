// Kiểm thử tích hợp API (MongoDB trong bộ nhớ hoặc TEST_MONGODB_URI).
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
const { signup, login } = require('./helpers/auth');

let token;
const api = () => request(app);
const auth = (r) => r.set('Authorization', `Bearer ${token}`);

before(async () => {
  await connectTestDb('finance_app_test');
});
after(async () => {
  await disconnectTestDb();
});

test('Ràng buộc dữ liệu khi đăng ký', async () => {
  const reg = (body) => api().post('/api/auth/register').send({ name: 'Nguyễn An', email: 'x@test.vn', password: 'Matkhau1', ...body });
  const cases = [
    [{ name: '' }, 'Vui lòng nhập họ tên'], [{ name: 'A' }, 'ít nhất 2'], [{ name: 'a'.repeat(51) }, 'tối đa 50'],
    [{ name: 'An123' }, 'chữ cái'], [{ email: '' }, 'nhập email'], [{ email: 'sai' }, 'không hợp lệ'],
    [{ email: 'a..b@test.vn' }, 'không hợp lệ'], [{ email: `${'a'.repeat(65)}@test.vn` }, 'quá dài'],
    [{ password: 'Ab1' }, 'ít nhất 8'], [{ password: 'abcdefgh' }, 'chữ cái và chữ số'],
    [{ password: '12345678' }, 'chữ cái và chữ số'], [{ password: 'Mat khau1' }, 'khoảng trắng'],
    [{ password: `A1${'a'.repeat(71)}` }, 'tối đa 72'], [{ email: 'abc12345@x.vn', password: 'abc12345@x.vn' }, 'trùng email'],
  ];
  for (const [body, msg] of cases) {
    const r = await reg(body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.match(r.body.error.message, new RegExp(msg), JSON.stringify(body));
  }
});

test('Đăng ký, đăng nhập bằng OTP gửi qua email, bảo vệ API', async () => {
  let r = await api().post('/api/auth/register').send({ name: '  Nguyễn   An ', email: 'an@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 201);
  assert.equal(r.body.otpRequired, true);
  assert.equal(r.body.token, undefined, 'chưa cấp token khi chưa nhập OTP');
  assert.match(r.body.devCode, /^\d{6}$/);
  // Email chưa xác thực: được đăng ký lại, mã cũ bị hủy
  const first = r.body;
  r = await api().post('/api/auth/register').send({ name: 'An', email: 'an@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 201);
  assert.equal((await api().post('/api/auth/verify-otp').send({ otpToken: first.otpToken, code: first.devCode })).status, 400);
  r = await api().post('/api/auth/verify-otp').send({ otpToken: r.body.otpToken, code: r.body.devCode });
  assert.equal(r.status, 200);
  assert.ok(r.body.token);
  assert.equal(r.body.user.emailVerified, true);
  r = await api().post('/api/auth/register').send({ name: 'An', email: 'AN@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 409);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: 'sai-mat-khau' });
  assert.equal(r.status, 401);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: '' });
  assert.equal(r.status, 400);
  r = await api().post('/api/auth/login').send({ email: 'an@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 200);
  assert.equal(r.body.otpRequired, true);
  assert.equal(r.body.token, undefined, 'đúng mật khẩu vẫn phải nhập OTP');
  const step = r.body;
  r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: '12ab56' });
  assert.equal(r.status, 400);
  r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: step.devCode === '000000' ? '111111' : '000000' });
  assert.equal(r.status, 400);
  assert.match(r.body.error.message, /còn 4 lần/);
  r = await api().post('/api/auth/resend-otp').send({ otpToken: step.otpToken });
  assert.equal(r.status, 429, 'phải đợi trước khi gửi lại');
  r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: step.devCode });
  assert.equal(r.status, 200);
  token = r.body.token;
  r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: step.devCode });
  assert.equal(r.status, 400, 'mã OTP chỉ dùng một lần');
  r = await api().get('/api/wallets');
  assert.equal(r.status, 401);
  r = await auth(api().get('/api/wallets'));
  assert.equal(r.status, 200);
  assert.equal(r.body.items[0].id, 'cash');
  r = await auth(api().get('/api/categories?income=false'));
  assert.equal(r.body.items.length, 7);
});

test('Ví: thêm, trùng tên, sửa, số dư tính từ giao dịch, xóa có ràng buộc', async () => {
  let r = await auth(api().post('/api/wallets')).send({ id: 'bank', name: 'Ngân hàng', opening: 1000000, currency: 'VND' });
  assert.equal(r.status, 201);
  assert.equal(r.body.balance, 1000000);
  r = await auth(api().post('/api/wallets')).send({ name: 'ngân hàng', opening: 0 });
  assert.equal(r.status, 409);
  r = await auth(api().post('/api/wallets')).send({ name: '', opening: 0 });
  assert.equal(r.status, 400);
  r = await auth(api().post('/api/wallets')).send({ id: 'save', name: 'Heo đất', savings: true, target: 5000000, startDate: '2026-10-01', deadline: '2026-09-01' });
  assert.equal(r.status, 400, 'ngày kết thúc trước ngày bắt đầu');
  r = await auth(api().put('/api/wallets/save')).send({ name: 'Heo đất', savings: true, target: 5000000, startDate: '2026-10-01', deadline: '2027-10-01' });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({ id: 't1', kind: 'expense', amount: 50000, walletId: 'bank', categoryId: 'food', date: '2026-10-05T08:00:00Z' });
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
  let r = await auth(api().put('/api/transactions/t1')).send({ kind: 'expense', amount: 80000, walletId: 'cash', categoryId: 'food', date: '2026-10-05T08:00:00Z' });
  assert.equal(r.status, 200);
  r = await auth(api().get('/api/wallets'));
  const bal = Object.fromEntries(r.body.items.map((w) => [w.id, w.balance]));
  assert.equal(bal.bank, 1000000);
  assert.equal(bal.cash, -80000);
  r = await auth(api().post('/api/transactions')).send({ kind: 'expense', amount: 10, walletId: 'cash', categoryId: 'salary', date: '2026-10-05' });
  assert.equal(r.status, 400, 'danh mục thu cho khoản chi');
  r = await auth(api().post('/api/transactions')).send({ kind: 'expense', amount: 0, walletId: 'cash', categoryId: 'food', date: '2026-10-05' });
  assert.equal(r.status, 400);
  r = await auth(api().post('/api/transactions')).send({ id: 'tr', kind: 'transfer', amount: 200000, walletId: 'bank', destinationId: 'cash', date: '2026-10-06' });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/people')).send({ id: 'binh', name: 'Bình', group: 'Bạn bè & Đồng nghiệp' });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({ kind: 'lend', amount: 100000, walletId: 'bank', date: '2026-10-07' });
  assert.equal(r.status, 400, 'vay nợ bắt buộc đối tượng');
  r = await auth(api().post('/api/transactions')).send({ id: 'l1', kind: 'lend', amount: 100000, walletId: 'bank', personId: 'binh', date: '2026-10-07', dueDate: '2026-10-01' });
  assert.equal(r.status, 400, 'hạn trước ngày giao dịch');
  r = await auth(api().post('/api/transactions')).send({ id: 'l1', kind: 'lend', amount: 100000, walletId: 'bank', personId: 'binh', date: '2026-10-07', dueDate: '2026-11-01' });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/transactions')).send({ kind: 'collect', amount: 150000, walletId: 'bank', personId: 'binh', date: '2026-10-08' });
  assert.equal(r.status, 400, 'thu nợ vượt số còn lại');
  r = await auth(api().post('/api/transactions')).send({ id: 'c1', kind: 'collect', amount: 40000, walletId: 'bank', personId: 'binh', date: '2026-10-08' });
  assert.equal(r.status, 201);
  r = await auth(api().get('/api/reports/debts'));
  assert.equal(r.body.people[0].receivable, 60000);
  r = await auth(api().get('/api/transactions?type=debt&sort=amount&order=desc'));
  assert.deepEqual(r.body.items.map((e) => e.id), ['l1', 'c1']);
  r = await auth(api().get('/api/transactions?q=Bình'));
  assert.equal(r.body.total, 2);
  r = await auth(api().get('/api/transactions?from=2026-10-06&to=2026-10-06T23:59:59'));
  assert.deepEqual(r.body.items.map((e) => e.id), ['tr']);
  r = await auth(api().delete('/api/people/binh'));
  assert.equal(r.status, 409);
});

test('Danh mục, ngân sách và báo cáo', async () => {
  let r = await auth(api().post('/api/categories')).send({ id: 'coffee', name: 'Cà phê', income: false, symbol: 15 });
  assert.equal(r.status, 201);
  r = await auth(api().post('/api/categories')).send({ name: 'cà phê', income: false });
  assert.equal(r.status, 409);
  r = await auth(api().post('/api/budgets')).send({ id: 'b1', categoryId: 'food', month: '2026-10-01', amount: 200000, currency: 'VND' });
  assert.equal(r.status, 201);
  assert.equal(r.body.used, 80000);
  r = await auth(api().post('/api/budgets')).send({ categoryId: 'food', walletId: 'cash', month: '2026-10-15', amount: 100000, currency: 'VND' });
  assert.equal(r.status, 409, 'ngân sách chồng lấn');
  r = await auth(api().post('/api/budgets')).send({ id: 'total', categoryId: null, month: '2026-10-01', amount: 3000000, currency: 'VND' });
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
  let r = await auth(api().post('/api/sync/batch')).send({ ops: [
    { entity: 'wallets', action: 'upsert', id: 'momo', data: { name: 'Ví điện tử', opening: 300000 } },
    { entity: 'entries', action: 'upsert', id: 'm1', data: { kind: 'income', amount: 1000, walletId: 'momo', categoryId: 'bonus', date: '2026-10-09' } },
    { entity: 'entries', action: 'delete', id: 'khong-ton-tai' },
    { entity: 'entries', action: 'upsert', id: 'bad', data: { kind: 'income', amount: -1, walletId: 'momo', categoryId: 'bonus', date: '2026-10-09' } },
  ] });
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
  assert.match(r.body.devCode, /^\d{6}$/);
  const code = r.body.devCode;
  r = await api().post('/api/auth/reset-password').send({ email: 'an@test.vn', code: '000000' === code ? '111111' : '000000', newPassword: 'Moi12345' });
  assert.equal(r.status, 400);
  r = await api().post('/api/auth/reset-password').send({ email: 'an@test.vn', code, newPassword: 'moi123' });
  assert.equal(r.status, 400, 'mật khẩu mới yếu');
  r = await api().post('/api/auth/reset-password').send({ email: 'an@test.vn', code, newPassword: 'Moi12345' });
  assert.equal(r.status, 200);
  token = r.body.token;
  token = (await login(app, 'an@test.vn', 'Moi12345')).token;
  r = await auth(api().put('/api/auth/me')).send({ name: 'An Nguyễn', currency: 'USD' });
  assert.equal(r.body.user.currency, 'USD');
  r = await auth(api().post('/api/auth/logout'));
  assert.equal(r.status, 204);
  r = await auth(api().get('/api/auth/me'));
  assert.equal(r.status, 401);
});

test('Dữ liệu tách biệt giữa người dùng', async () => {
  const t2 = (await signup(app, 'Bảo', 'bao@test.vn', 'Matkhau1')).token;
  const r = await api().get('/api/transactions').set('Authorization', `Bearer ${t2}`);
  assert.equal(r.body.total, 0);
  const w = await api().get('/api/wallets').set('Authorization', `Bearer ${t2}`);
  assert.equal(w.body.items.length, 1);
  assert.equal(w.body.items[0].balance, 0);
});

test('Đăng xuất chỉ thu hồi phiên của thiết bị đó; { all: true } đăng xuất mọi thiết bị', async () => {
  await signup(app, 'Đa', 'da@test.vn', 'Matkhau1');
  const a = await login(app, 'da@test.vn', 'Matkhau1');
  const b = await login(app, 'da@test.vn', 'Matkhau1');
  const me = (t) => api().get('/api/auth/me').set('Authorization', `Bearer ${t}`);
  assert.equal((await me(a.token)).status, 200);
  assert.equal((await api().post('/api/auth/logout').set('Authorization', `Bearer ${a.token}`)).status, 204);
  assert.equal((await me(a.token)).status, 401, 'thiết bị A đã đăng xuất');
  assert.equal((await api().post('/api/auth/refresh').send({ refreshToken: a.refreshToken })).status, 401);
  assert.equal((await me(b.token)).status, 200, 'thiết bị B vẫn đăng nhập');
  // Làm mới token giữ nguyên phiên của thiết bị B
  const b2 = (await api().post('/api/auth/refresh').send({ refreshToken: b.refreshToken })).body;
  assert.equal((await me(b2.token)).status, 200);
  const c = await login(app, 'da@test.vn', 'Matkhau1');
  assert.equal((await api().post('/api/auth/logout').set('Authorization', `Bearer ${c.token}`).send({ all: true })).status, 204);
  assert.equal((await me(b2.token)).status, 401, 'đăng xuất mọi thiết bị');
});

test('Khóa đăng nhập sau nhiều lần sai mật khẩu; giới hạn nhập sai OTP', async () => {
  await signup(app, 'Khóa', 'khoa@test.vn', 'Matkhau1');
  const step = (await api().post('/api/auth/login').send({ email: 'khoa@test.vn', password: 'Matkhau1' })).body;
  const wrong = step.devCode === '000000' ? '111111' : '000000';
  let r;
  for (let i = 0; i < config.otp.maxAttempts; i += 1) {
    r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: wrong });
  }
  assert.equal(r.body.error.code, 'OTP_EXPIRED', 'sai quá số lần thì phiên OTP bị hủy');
  r = await api().post('/api/auth/verify-otp').send({ otpToken: step.otpToken, code: step.devCode });
  assert.equal(r.status, 400);
  for (let i = 0; i < config.maxFailedLogins; i += 1) {
    r = await api().post('/api/auth/login').send({ email: 'khoa@test.vn', password: 'SaiMatKhau9' });
    assert.equal(r.status, 401);
  }
  r = await api().post('/api/auth/login').send({ email: 'khoa@test.vn', password: 'Matkhau1' });
  assert.equal(r.status, 429);
  assert.equal(r.body.error.code, 'ACCOUNT_LOCKED');
});
