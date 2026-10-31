// Dựng "snapshot" dữ liệu tài chính gửi sang AI service (AI service không lưu dữ liệu người dùng).
// - Quy đổi mọi giao dịch về tiền tệ báo cáo của người dùng theo tỷ giá đã lưu (bỏ qua ví không có tỷ giá).
// - Không gửi thông tin tài khoản (email, mật khẩu, token).
const L = require('./ledger');

/** Thời điểm hiện tại dạng ISO kèm độ lệch múi giờ của máy chủ (process.env.TZ), ví dụ 2026-10-29T09:30:00+07:00. */
function localIso(d = new Date()) {
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? '+' : '-';
  const pad = (n) => String(Math.trunc(Math.abs(n))).padStart(2, '0');
  const local = new Date(d.getTime() + off * 60000).toISOString().slice(0, 19);
  return `${local}${sign}${pad(off / 60)}:${pad(off % 60)}`;
}

function converter(user) {
  const cur = user.currency || 'VND';
  const rates = user.rates instanceof Map ? Object.fromEntries(user.rates) : (user.rates || {});
  const toVnd = (amount, c) => (c === 'VND' ? amount : rates[c] ? amount * rates[c] : null);
  return (amount, c) => {
    if (c === cur) return amount;
    const v = toVnd(amount, c);
    if (v == null) return null;
    if (cur === 'VND') return v;
    return rates[cur] ? v / rates[cur] : null;
  };
}

function buildSnapshot(state, user, { maxTransactions = 15000, now = new Date() } = {}) {
  const convert = converter(user);
  const walletCur = Object.fromEntries(state.wallets.map((w) => [w.id, w.currency]));
  const transactions = [];
  const sorted = [...state.entries].sort((a, b) => new Date(a.date) - new Date(b.date)).slice(-maxTransactions);
  for (const e of sorted) {
    const amount = convert(e.amount, walletCur[e.walletId]);
    if (amount == null) continue;
    transactions.push({
      id: e.id, kind: e.kind, amount, date: new Date(e.date).toISOString(), categoryId: e.categoryId || null,
      personId: e.personId || null, walletId: e.walletId, note: (e.note || '').slice(0, 300), excluded: Boolean(e.excluded),
    });
  }
  const thisMonth = L.monthStart(now);
  return {
    currency: user.currency || 'VND',
    now: localIso(now),
    wallets: state.wallets.filter((w) => !w.excluded).map((w) => ({
      id: w.id, name: w.name, currency: w.currency, savings: Boolean(w.savings), target: w.target || 0,
      balance: convert(L.balance(state, w.id), w.currency) ?? 0,
    })),
    categories: state.categories.map((c) => ({ id: c.id, name: c.name, income: Boolean(c.income) })),
    people: state.people.map((p) => ({ id: p.id, name: p.name })),
    transactions,
    budgets: state.budgets.filter((b) => L.sameMonth(L.monthValue(b.month), thisMonth)).map((b) => ({
      id: b.id, categoryId: b.categoryId || null, amount: convert(b.amount, b.currency) ?? b.amount,
      used: convert(L.used(state, b), b.currency) ?? 0, income: Boolean(b.income),
    })),
  };
}

/** Lịch sử ghi chú đã gán danh mục — dữ liệu cá nhân hóa cho bộ phân loại. */
const labeledHistory = (state, limit = 2000) => state.entries
  .filter((e) => e.categoryId && e.note && e.note.trim())
  .slice(-limit)
  .map((e) => ({ text: e.note.slice(0, 500), categoryId: e.categoryId }));

module.exports = { buildSnapshot, labeledHistory, localIso };
