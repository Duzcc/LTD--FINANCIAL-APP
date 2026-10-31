// Kiểm tra toàn hệ thống qua HTTP như ứng dụng thật: tài khoản → dữ liệu → báo cáo → AI.
import { readFileSync } from 'node:fs';
const API = process.env.API || 'http://localhost:3000/api';
const AI = process.env.AI || 'http://localhost:8000';
const results = [];
let token, refresh;
async function call(method, path, body, { auth = true, base = API, headers = {} } = {}) {
  const res = await fetch(base + path, {
    method, headers: { 'content-type': 'application/json', ...(auth && token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = null; try { data = await res.json(); } catch {}
  return { status: res.status, data };
}
async function check(name, fn) {
  const t0 = Date.now();
  try { const info = await fn(); results.push(['✅', name, `${Date.now() - t0}ms`, info ?? '']); }
  catch (e) { results.push(['❌', name, `${Date.now() - t0}ms`, String(e.message).slice(0, 160)]); }
}
const expect = (c, msg) => { if (!c) throw new Error(msg); };
const now = new Date();
const day = (d) => new Date(now.getFullYear(), now.getMonth(), now.getDate() - d, 12).toISOString();
const email = `kiemtra${Date.now() % 1e6}@nhom3.vn`;

await check('Backend & AI service sống', async () => {
  const a = await call('GET', '/health', undefined, { auth: false }); const b = await call('GET', '/health', undefined, { base: AI, auth: false });
  expect(a.data?.db === 'connected' && b.data?.modelsLoaded, JSON.stringify([a.data, b.data])); return `db=${a.data.db}, models=${b.data.modelsLoaded}`;
});
await check('AI service từ chối gọi trực tiếp không có khóa', async () => {
  const r = await call('POST', '/v1/parse', { text: 'phở 45k' }, { base: AI, auth: false }); expect(r.status === 401, `status ${r.status}`); return '401';
});
await check('Đăng ký', async () => {
  const r = await call('POST', '/auth/register', { name: 'Kiểm Tra', email, password: 'matkhau123' }, { auth: false });
  expect(r.status === 201, JSON.stringify(r.data)); token = r.data.token; refresh = r.data.refreshToken; return email;
});
await check('Đăng nhập sai mật khẩu bị chặn', async () => {
  const r = await call('POST', '/auth/login', { email, password: 'sai' }, { auth: false }); expect(r.status === 401, r.status); return '401';
});
await check('Refresh token xoay vòng', async () => {
  const r = await call('POST', '/auth/refresh', { refreshToken: refresh }, { auth: false });
  expect(r.status === 200 && r.data.token, r.status); token = r.data.token;
  const again = await call('POST', '/auth/refresh', { refreshToken: refresh }, { auth: false });
  expect(again.status === 401, `token cũ vẫn dùng được: ${again.status}`); refresh = r.data.refreshToken; return 'token cũ bị thu hồi';
});
await check('Không có token → 401', async () => {
  const t = token; token = null; const r = await call('GET', '/wallets'); token = t; expect(r.status === 401, r.status); return '401';
});
await check('Tạo ví ngân hàng + ví tiết kiệm', async () => {
  const a = await call('POST', '/wallets', { id: 'bank', name: 'Vietcombank', currency: 'VND', opening: 15000000 });
  const b = await call('POST', '/wallets', { id: 'save', name: 'Tiết kiệm', currency: 'VND', opening: 0, savings: true, target: 20000000 });
  expect(a.status === 201 && b.status === 201, JSON.stringify([a.data, b.data])); return 'bank, save';
});
await check('Đồng bộ hàng loạt 90 ngày giao dịch (sync/batch)', async () => {
  const ops = []; let n = 0;
  const add = (data) => ops.push({ entity: 'entries', action: 'upsert', id: `t${n++}`, data });
  for (let d = 0; d < 90; d++) {
    add({ kind: 'expense', amount: [45000, 40000, 50000][d % 3], date: day(d), walletId: 'cash', categoryId: 'food', note: ['Phở bò', 'Cơm trưa', 'Bún chả'][d % 3] });
    if (d % 2) add({ kind: 'expense', amount: 35000, date: day(d), walletId: 'cash', categoryId: 'food', note: 'cà phê highlands' });
    if (d % 4 === 0) add({ kind: 'expense', amount: 60000, date: day(d), walletId: 'bank', categoryId: 'transport', note: 'grab đi làm' });
  }
  for (const m of [0, 1, 2]) add({ kind: 'income', amount: 18000000, date: new Date(now.getFullYear(), now.getMonth() - m, 5, 9).toISOString(), walletId: 'bank', categoryId: 'salary', note: 'Lương tháng' });
  add({ kind: 'expense', amount: 2500000, date: day(1), walletId: 'bank', categoryId: 'food', note: 'Nhà hàng sinh nhật' });
  ops.push({ entity: 'people', action: 'upsert', id: 'minh', data: { name: 'Minh', group: 'Bạn bè & Đồng nghiệp' } });
  add({ kind: 'lend', amount: 500000, date: day(3), walletId: 'cash', personId: 'minh', note: 'cho Minh mượn' });
  add({ kind: 'transfer', amount: 2000000, date: day(2), walletId: 'bank', destinationId: 'save', note: 'để dành' });
  const r = await call('POST', '/sync/batch', { ops });
  if (r.status !== 200) { // khoản cho vay cần đối tượng → tạo rồi gửi lại
    throw new Error(JSON.stringify(r.data));
  }
  return `${r.data.applied} thao tác`;
});
await check('Quy tắc nghiệp vụ: vay/nợ thiếu đối tượng bị từ chối', async () => {
  const r = await call('POST', '/sync/batch', { ops: [{ entity: 'entries', action: 'upsert', id: 'x1', data: { kind: 'lend', amount: 1000, date: day(0), walletId: 'cash' } }] });
  expect(r.status === 400, r.status); return r.data.error.message;
});
await check('Công nợ: Minh nợ 500.000đ', async () => {
  const r = await call('GET', '/reports/debts'); const s = JSON.stringify(r.data); expect(r.status === 200 && s.includes('500000'), s.slice(0, 200)); return 'OK';
});
await check('Tổng quan (dashboard) và số dư', async () => {
  const r = await call('GET', '/reports/dashboard'); expect(r.status === 200, JSON.stringify(r.data));
  const w = await call('GET', '/wallets'); const bank = w.data.find?.((x) => x.id === 'bank') ?? (w.data.items || w.data.wallets || []).find((x) => x.id === 'bank');
  return `số dư Vietcombank = ${bank?.balance?.toLocaleString('vi-VN')}`;
});
await check('Thống kê theo danh mục (summary)', async () => { const r = await call('GET', '/reports/summary'); expect(r.status === 200, r.status); return 'OK'; });
await check('Lọc giao dịch (q=phở)', async () => {
  const r = await call('GET', '/transactions?q=ph%E1%BB%9F'); expect(r.status === 200, r.status);
  const list = Array.isArray(r.data) ? r.data : r.data.items || r.data.transactions || []; return `${list.length} kết quả`;
});
await check('AI: trạng thái', async () => { const r = await call('GET', '/ai/status'); expect(r.data.provider === 'ai-service', JSON.stringify(r.data)); return r.data.features.join(', '); });
await check('AI: gợi ý danh mục cá nhân hóa', async () => {
  const r = await call('POST', '/ai/categorize', { text: 'highlands', income: false }); expect(r.data.predictions?.[0]?.categoryId === 'food', JSON.stringify(r.data));
  return `food ${(r.data.predictions[0].probability * 100).toFixed(0)}%, trọng số cá nhân ${r.data.personalWeight}`;
});
for (const [text, kind] of [['ăn phở 45k sáng nay', 'expense'], ['cho Minh mượn 500k', 'lend'], ['Linh cho mình mượn 200k', 'borrow'], ['trả lãi vay ngân hàng 1tr', 'interestExpense'], ['chuyển 2tr từ Vietcombank sang tiết kiệm', 'transfer']]) {
  await check(`AI: nhập nhanh "${text}"`, async () => {
    const r = await call('POST', '/ai/parse', { text }); expect(r.data.kind === kind, JSON.stringify(r.data));
    return `${r.data.kind} ${r.data.amount?.toLocaleString('vi-VN')}đ, tin cậy ${r.data.confidence}`;
  });
}
await check('AI: dự báo cuối tháng', async () => {
  const r = await call('GET', '/ai/forecast'); expect(r.data.projected >= r.data.spent, JSON.stringify(r.data));
  return `đã chi ${r.data.spent.toLocaleString('vi-VN')} → dự báo ${r.data.projected.toLocaleString('vi-VN')} (${r.data.lower.toLocaleString('vi-VN')}–${r.data.upper.toLocaleString('vi-VN')})`;
});
await check('AI: phát hiện bất thường (bữa 2,5tr)', async () => {
  const r = await call('GET', '/ai/anomalies'); const hit = r.data.anomalies?.find((a) => a.transactionId === `t${0}` || a.reasons.join().includes('Ăn uống'));
  expect(hit, JSON.stringify(r.data).slice(0, 200)); return hit.reasons[0];
});
await check('AI: gợi ý ngân sách', async () => {
  const r = await call('GET', '/ai/budgets/recommend?savingsRate=0.2'); expect(r.data.suggestions?.length, JSON.stringify(r.data));
  return r.data.suggestions.map((s) => `${s.categoryId} ${s.amount.toLocaleString('vi-VN')}`).join(', ');
});
await check('AI: tổng hợp trang chủ (insights)', async () => {
  const r = await call('GET', '/ai/insights'); expect(r.data.forecast && r.data.anomalies && r.data.budgets, 'thiếu phần'); return 'đủ 3 phần';
});
await check('AI: tìm kiếm "grab tuần này"', async () => {
  const r = await call('POST', '/ai/search', { query: 'grab tuần này' }); expect(r.data.hits?.length, JSON.stringify(r.data)); return `${r.data.hits.length} kết quả, lọc ${Object.keys(r.data.filters).join(',')}`;
});
for (const q of ['tháng này mình chi bao nhiêu?', 'dự báo cuối tháng', 'có giao dịch nào bất thường không?', 'ghi giúp trà sữa 35k']) {
  await check(`AI: trợ lý "${q}"`, async () => {
    const r = await call('POST', '/ai/chat', { messages: [{ role: 'user', content: q }] }); expect(r.data.reply, JSON.stringify(r.data));
    return `${r.data.source}${r.data.actions?.length ? ` + đề xuất ${r.data.actions[0].type}` : ''}: ${r.data.reply.replace(/\n/g, ' ').slice(0, 90)}`;
  });
}
await check('AI: đọc hóa đơn từ văn bản', async () => {
  const r = await call('POST', '/ai/receipts/text', { text: 'CIRCLE K\nNgày 18/10/2026\nMì ly 9.000\nBánh mì 25.000\nNước suối 12.000\nTỔNG CỘNG 46.000\nTiền khách đưa 100.000\nTiền thừa 54.000' });
  expect(r.data.total === 46000, JSON.stringify(r.data)); return `${r.data.merchant} ${r.data.total.toLocaleString('vi-VN')}đ, tin cậy ${r.data.confidence}`;
});
await check('AI: quét ẢNH hóa đơn trên máy chủ (OCR)', async () => {
  const img = readFileSync(process.env.RECEIPT_IMG).toString('base64'); const label = JSON.parse(readFileSync(process.env.RECEIPT_LABEL, 'utf8'));
  const r = await call('POST', '/ai/receipts/scan', { image: img, mediaType: 'image/jpeg' });
  expect(r.data.total === label.total, `cần ${label.total}, đọc ${JSON.stringify(r.data).slice(0, 200)}`);
  return `${r.data.source}: ${r.data.merchant} ${r.data.total.toLocaleString('vi-VN')}đ, tin cậy ${r.data.confidence}`;
});
await check('Xóa tài khoản và toàn bộ dữ liệu', async () => {
  const r = await call('DELETE', '/auth/me', { password: 'matkhau123' }); expect(r.status === 200 || r.status === 204, r.status);
  const after = await call('POST', '/auth/login', { email, password: 'matkhau123' }, { auth: false }); expect(after.status === 401, after.status); return 'đã xóa';
});
for (const [ok, name, ms, info] of results) console.log(`${ok} ${name} (${ms})${info ? ' — ' + info : ''}`);
const failed = results.filter((r) => r[0] === '❌').length;
console.log(`\nTỔNG: ${results.length - failed}/${results.length} đạt`);
