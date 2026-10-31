// Nghiệp vụ sổ cái: tính số dư, kiểm tra ràng buộc dữ liệu. Logic này khớp với FinanceProvider ở app.
const { KINDS, isDebt, isIncome, isExpense, CURRENCIES, CATEGORY_SYMBOLS } = require('./constants');
const { badRequest, conflict } = require('./errors');

const str = (v) => (v === undefined || v === null ? '' : String(v)).trim();
const optStr = (v) => (str(v) === '' ? null : str(v));
const bool = (v) => v === true || v === 'true';
function num(v, field) {
  const n = typeof v === 'string' ? Number(v.replace(',', '.')) : Number(v);
  if (v === undefined || v === null || v === '' || !Number.isFinite(n)) throw badRequest(`${field} không hợp lệ.`);
  return n;
}
function date(v, field, required = false) {
  if (v === undefined || v === null || v === '') {
    if (required) throw badRequest(`${field} là bắt buộc.`);
    return null;
  }
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) throw badRequest(`${field} không hợp lệ.`);
  return d;
}
const dayStart = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const monthStart = (d) => new Date(d.getFullYear(), d.getMonth(), 1);
const monthEnd = (d) => new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999);
const sameMonth = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
const byId = (list, id) => list.find((x) => x.id === id);

function balance(state, walletId) {
  const w = byId(state.wallets, walletId);
  if (!w) return 0;
  return state.entries.reduce((sum, e) => {
    let s = sum;
    if (e.walletId === walletId) s += e.amount * KINDS[e.kind].sign;
    if (e.kind === 'transfer' && e.destinationId === walletId) s += e.amount;
    return s;
  }, w.opening);
}

/** Dư nợ còn lại: borrowed=true → số phải trả; false → số cần thu. */
function outstanding(state, { borrowed, personId, currency, excludeId }) {
  const principal = borrowed ? 'borrow' : 'lend';
  const settle = borrowed ? 'repay' : 'collect';
  return state.entries
    .filter((e) => e.id !== excludeId && (personId == null || e.personId === personId))
    .filter((e) => { const w = byId(state.wallets, e.walletId); return w && (!currency || w.currency === currency); })
    .reduce((s, e) => s + (e.kind === principal ? e.amount : e.kind === settle ? -e.amount : 0), 0);
}

function validateWallet(state, input, id) {
  const prev = byId(state.wallets, id);
  const w = {
    id,
    name: str(input.name),
    savings: bool(input.savings),
    currency: str(input.currency || 'VND').toUpperCase(),
    opening: num(input.opening ?? 0, 'Số dư ban đầu'),
    target: num(input.target ?? 0, 'Số tiền mục tiêu'),
    startDate: date(input.startDate, 'Ngày bắt đầu'),
    deadline: date(input.deadline, 'Ngày kết thúc'),
    excluded: bool(input.excluded),
  };
  if (!w.name) throw badRequest('Vui lòng nhập tên ví.');
  if (!CURRENCIES.includes(w.currency)) throw badRequest('Đơn vị tiền tệ không được hỗ trợ.');
  if (w.opening < 0 || w.target < 0) throw badRequest('Số tiền không được âm.');
  if (!w.savings) { w.target = 0; w.startDate = null; w.deadline = null; }
  if (w.startDate && w.deadline && dayStart(w.deadline) < dayStart(w.startDate)) {
    throw badRequest('Ngày kết thúc phải sau ngày bắt đầu.');
  }
  if (state.wallets.some((x) => x.id !== id && x.name.toLowerCase() === w.name.toLowerCase())) {
    throw conflict('Tên ví đã tồn tại. Vui lòng đặt tên khác.', 'DUPLICATE_NAME');
  }
  if (prev && prev.currency !== w.currency && walletRefs(state, id).total > 0) {
    throw conflict('Ví đã có giao dịch hoặc ngân sách nên không thể đổi tiền tệ.');
  }
  return w;
}

function walletRefs(state, id) {
  const entries = state.entries.filter((e) => e.walletId === id || e.destinationId === id).length;
  const budgets = state.budgets.filter((b) => b.walletId === id).length;
  const recurring = (state.recurring || []).filter((r) => r.walletId === id || r.destinationId === id).length;
  return { entries, budgets, recurring, total: entries + budgets + recurring };
}

function validateCategory(state, input, id) {
  const c = {
    id,
    name: str(input.name),
    income: bool(input.income),
    symbol: Math.trunc(num(input.symbol ?? 0, 'Biểu tượng')),
    isDefault: bool(input.isDefault),
  };
  if (!c.name) throw badRequest('Vui lòng nhập tên danh mục.');
  if (c.symbol < 0 || c.symbol >= CATEGORY_SYMBOLS) c.symbol = 0;
  if (state.categories.some((x) => x.id !== id && x.income === c.income && x.name.toLowerCase() === c.name.toLowerCase())) {
    throw conflict('Tên danh mục đã tồn tại.', 'DUPLICATE_NAME');
  }
  const prev = byId(state.categories, id);
  if (prev && prev.income !== c.income && categoryRefs(state, id) > 0) {
    throw conflict('Danh mục đang được sử dụng nên không thể đổi loại thu/chi.');
  }
  return c;
}
const categoryRefs = (state, id) =>
  state.entries.filter((e) => e.categoryId === id).length + state.budgets.filter((b) => b.categoryId === id).length
  + (state.recurring || []).filter((r) => r.categoryId === id).length;

function validatePerson(state, input, id) {
  const p = { id, name: str(input.name), group: str(input.group) || 'Cá nhân' };
  if (!p.name) throw badRequest('Vui lòng nhập tên đối tượng.');
  return p;
}
const personRefs = (state, id) => state.entries.filter((e) => e.personId === id).length
  + (state.recurring || []).filter((r) => r.personId === id).length;

function validateEntry(state, input, id, { checkDebt = true } = {}) {
  const kind = str(input.kind);
  if (!KINDS[kind]) throw badRequest('Loại giao dịch không hợp lệ.');
  const e = {
    id,
    kind,
    amount: num(input.amount, 'Số tiền'),
    walletId: str(input.walletId),
    destinationId: kind === 'transfer' ? optStr(input.destinationId) : null,
    categoryId: isIncome(kind) || isExpense(kind) ? optStr(input.categoryId) : null,
    personId: optStr(input.personId),
    date: date(input.date, 'Ngày giao dịch', true),
    dueDate: isDebt(kind) ? date(input.dueDate, 'Ngày đến hạn') : null,
    note: str(input.note).slice(0, 500),
    excluded: bool(input.excluded),
    recurringId: optStr(input.recurringId),
  };
  if (e.amount <= 0) throw badRequest('Số tiền phải lớn hơn 0.');
  const wallet = byId(state.wallets, e.walletId);
  if (!wallet) throw badRequest('Vui lòng chọn ví hợp lệ.');
  if (kind === 'transfer') {
    const dest = byId(state.wallets, e.destinationId);
    if (!dest || dest.id === wallet.id) throw badRequest('Chọn hai ví khác nhau.');
    if (dest.currency !== wallet.currency) throw badRequest('Chỉ chuyển giữa hai ví cùng tiền tệ.');
  }
  if (isIncome(kind) || isExpense(kind)) {
    const c = byId(state.categories, e.categoryId);
    if (!c || c.income !== isIncome(kind)) throw badRequest('Chọn danh mục phù hợp với giao dịch.');
  }
  if (e.personId && !byId(state.people, e.personId)) throw badRequest('Đối tượng không tồn tại.');
  if (isDebt(kind) && !e.personId) throw badRequest('Chọn đối tượng cho giao dịch vay/nợ.');
  if (e.dueDate && dayStart(e.dueDate) < dayStart(e.date)) {
    throw badRequest('Ngày đến hạn không được trước ngày giao dịch.');
  }
  if (checkDebt && (kind === 'collect' || kind === 'repay')) {
    const left = outstanding(state, { borrowed: kind === 'repay', personId: e.personId, currency: wallet.currency, excludeId: id });
    if (e.amount > left + 1e-9) {
      throw badRequest(kind === 'repay'
        ? `Số tiền trả nợ vượt số còn phải trả (${left}).`
        : `Số tiền thu nợ vượt số còn phải thu (${left}).`);
    }
  }
  return e;
}

// "2026-10" hoặc "2026-10-01" → ngày đầu tháng theo giờ máy chủ (không phụ thuộc UTC).
function monthValue(v) {
  const m = /^(\d{4})-(\d{2})/.exec(String(v || ''));
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, 1);
  return date(v, 'Tháng', true);
}
const monthKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;

const FREQUENCIES = ['daily', 'weekly', 'monthly', 'yearly'];
function validateRecurring(state, input, id) {
  const base = validateEntry(state, { ...input, date: input.startDate }, id, { checkDebt: false });
  const r = {
    id,
    kind: base.kind,
    amount: base.amount,
    walletId: base.walletId,
    destinationId: base.destinationId,
    categoryId: base.categoryId,
    personId: base.personId,
    note: base.note,
    frequency: FREQUENCIES.includes(input.frequency) ? input.frequency : 'monthly',
    interval: Math.min(365, Math.max(1, Math.trunc(num(input.interval ?? 1, 'Chu kỳ')))),
    startDate: base.date,
    endDate: date(input.endDate, 'Ngày kết thúc'),
    nextDate: date(input.nextDate, 'Lần kế tiếp'),
    active: input.active !== false,
  };
  if (r.endDate && dayStart(r.endDate) < dayStart(r.startDate)) throw badRequest('Ngày kết thúc phải sau ngày bắt đầu.');
  return r;
}

function validateBudget(state, input, id) {
  const month = monthValue(input.month);
  const b = {
    id,
    amount: num(input.amount, 'Số tiền ngân sách'),
    month: monthStart(month),
    categoryId: optStr(input.categoryId),
    walletId: optStr(input.walletId),
    currency: str(input.currency || 'VND').toUpperCase(),
    income: bool(input.income),
  };
  b.startDate = b.month;
  b.endDate = monthEnd(b.month);
  if (b.amount <= 0) throw badRequest('Nhập số tiền ngân sách lớn hơn 0.');
  if (b.categoryId) {
    const c = byId(state.categories, b.categoryId);
    if (!c) throw badRequest('Danh mục không tồn tại.');
    b.income = c.income;
  }
  if (b.walletId) {
    const w = byId(state.wallets, b.walletId);
    if (!w) throw badRequest('Ví không tồn tại.');
    if (w.currency !== b.currency) throw badRequest('Tiền tệ không khớp với ví.');
  }
  const overlap = state.budgets.some((v) => v.id !== id && v.categoryId === b.categoryId && v.income === b.income
    && v.currency === b.currency && sameMonth(monthValue(v.month), b.month)
    && (v.walletId === b.walletId || v.walletId == null || b.walletId == null));
  if (overlap) throw conflict('Ngân sách cho danh mục và ví trong tháng này đã tồn tại.', 'DUPLICATE_BUDGET');
  return b;
}

function used(state, b) {
  const m = monthValue(b.month);
  return state.entries
    .filter((e) => !e.excluded && sameMonth(new Date(e.date), m))
    .filter((e) => (b.income ? isIncome(e.kind) : isExpense(e.kind)))
    .filter((e) => !b.categoryId || e.categoryId === b.categoryId)
    .filter((e) => (b.walletId ? e.walletId === b.walletId : true))
    .filter((e) => { const w = byId(state.wallets, e.walletId); return w && w.currency === b.currency; })
    .reduce((s, e) => s + e.amount, 0);
}

module.exports = {
  balance, outstanding, used, walletRefs, categoryRefs, personRefs,
  validateWallet, validateCategory, validatePerson, validateEntry, validateBudget, validateRecurring,
  monthStart, monthEnd, sameMonth, byId, date, monthValue, monthKey,
};
