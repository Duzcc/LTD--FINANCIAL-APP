const router = require('express').Router();
const wrap = require('../middleware/async');
const { loadState } = require('../services/store');
const L = require('../services/ledger');
const { isIncome, isExpense, isDebt } = require('../services/constants');

const inCurrency = (state, cur) => (e) => L.byId(state.wallets, e.walletId)?.currency === cur;
const sum = (list) => list.reduce((s, e) => s + e.amount, 0);

// Dashboard: số dư, thu chi tháng, ngân sách, giao dịch gần đây, chi theo danh mục, công nợ
router.get('/dashboard', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  const cur = req.query.currency || req.user.currency || 'VND';
  const month = L.monthStart(req.query.month ? L.monthValue(req.query.month) : new Date());
  const prev = new Date(month.getFullYear(), month.getMonth() - 1, 1);
  const monthly = (m) => state.entries.filter((e) => !e.excluded && L.sameMonth(new Date(e.date), m) && inCurrency(state, cur)(e));
  const cur_ = monthly(month);
  const prev_ = monthly(prev);
  const expenseByCategory = state.categories.filter((c) => !c.income).map((c) => ({
    categoryId: c.id, name: c.name, amount: sum(cur_.filter((e) => isExpense(e.kind) && e.categoryId === c.id)),
  })).filter((x) => x.amount > 0).sort((a, b) => b.amount - a.amount);
  const wallets = state.wallets.filter((w) => w.currency === cur).map((w) => ({ ...w, balance: L.balance(state, w.id) }));
  res.json({
    currency: cur,
    month: month.toISOString(),
    totalBalance: wallets.filter((w) => !w.excluded).reduce((s, w) => s + w.balance, 0),
    income: sum(cur_.filter((e) => isIncome(e.kind))),
    expense: sum(cur_.filter((e) => isExpense(e.kind))),
    previousIncome: sum(prev_.filter((e) => isIncome(e.kind))),
    previousExpense: sum(prev_.filter((e) => isExpense(e.kind))),
    wallets,
    expenseByCategory,
    budgets: state.budgets.filter((b) => b.currency === cur && L.sameMonth(L.monthValue(b.month), month))
      .map((b) => ({ ...b, used: L.used(state, b) })),
    debt: {
      payable: L.outstanding(state, { borrowed: true, currency: cur }),
      receivable: L.outstanding(state, { borrowed: false, currency: cur }),
    },
    recent: state.entries.filter(inCurrency(state, cur)).sort((a, b) => new Date(b.date) - new Date(a.date)).slice(0, 5),
  });
}));

// Thống kê theo khoảng thời gian: chuỗi thu/chi theo ngày hoặc tháng và theo danh mục
router.get('/summary', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  const cur = req.query.currency || req.user.currency || 'VND';
  const now = new Date();
  const from = L.date(req.query.from, 'from') || L.monthStart(now);
  const to = L.date(req.query.to, 'to') || L.monthEnd(now);
  const groupBy = req.query.groupBy === 'month' ? 'month' : 'day';
  const list = state.entries.filter((e) => !e.excluded && inCurrency(state, cur)(e) && new Date(e.date) >= from && new Date(e.date) <= to);
  const keyOf = (d) => (groupBy === 'month'
    ? `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
  const series = {};
  for (const e of list) {
    const k = keyOf(new Date(e.date));
    series[k] = series[k] || { period: k, income: 0, expense: 0 };
    if (isIncome(e.kind)) series[k].income += e.amount;
    if (isExpense(e.kind)) series[k].expense += e.amount;
  }
  const byCategory = state.categories.map((c) => ({
    categoryId: c.id, name: c.name, income: c.income,
    amount: sum(list.filter((e) => e.categoryId === c.id && (c.income ? isIncome(e.kind) : isExpense(e.kind)))),
  })).filter((x) => x.amount > 0).sort((a, b) => b.amount - a.amount);
  res.json({
    currency: cur, from: from.toISOString(), to: to.toISOString(), groupBy,
    income: sum(list.filter((e) => isIncome(e.kind))),
    expense: sum(list.filter((e) => isExpense(e.kind))),
    series: Object.values(series).sort((a, b) => a.period.localeCompare(b.period)),
    byCategory,
  });
}));

// Sổ nợ theo đối tượng
router.get('/debts', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  const cur = req.query.currency || req.user.currency || 'VND';
  const people = state.people.map((p) => ({
    personId: p.id, name: p.name,
    payable: L.outstanding(state, { borrowed: true, personId: p.id, currency: cur }),
    receivable: L.outstanding(state, { borrowed: false, personId: p.id, currency: cur }),
    entries: state.entries.filter((e) => isDebt(e.kind) && e.personId === p.id && inCurrency(state, cur)(e)),
  })).filter((p) => p.entries.length > 0);
  res.json({ currency: cur, people });
}));

module.exports = router;
