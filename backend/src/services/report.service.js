const ledger = require('./ledger.service');
const L = require('../domain/ledger');
const { isIncome, isExpense, isDebt } = require('../domain/constants');

const sum = (list) => list.reduce((s, e) => s + e.amount, 0);
const pad = (n) => String(n).padStart(2, '0');
const currencyOf = (user, query) => query.currency || user.currency || 'VND';
const inCurrency = (state, currency) => (e) => L.byId(state.wallets, e.walletId)?.currency === currency;
const byNewest = (a, b) => new Date(b.date) - new Date(a.date);

function totals(list) {
  return { income: sum(list.filter((e) => isIncome(e.kind))), expense: sum(list.filter((e) => isExpense(e.kind))) };
}

async function dashboard(user, query) {
  const state = await ledger.loadState(user._id);
  const currency = currencyOf(user, query);
  const month = L.monthStart(query.month ? L.monthValue(query.month) : new Date());
  const previousMonth = new Date(month.getFullYear(), month.getMonth() - 1, 1);
  const entriesOf = (m) =>
    state.entries.filter((e) => !e.excluded && L.sameMonth(new Date(e.date), m) && inCurrency(state, currency)(e));
  const current = entriesOf(month);
  const previous = totals(entriesOf(previousMonth));
  const wallets = state.wallets
    .filter((w) => w.currency === currency)
    .map((w) => ({ ...w, balance: L.balance(state, w.id) }));
  const expenseByCategory = state.categories
    .filter((c) => !c.income)
    .map((c) => ({
      categoryId: c.id,
      name: c.name,
      amount: sum(current.filter((e) => isExpense(e.kind) && e.categoryId === c.id)),
    }))
    .filter((x) => x.amount > 0)
    .sort((a, b) => b.amount - a.amount);
  return {
    currency,
    month: month.toISOString(),
    totalBalance: wallets.filter((w) => !w.excluded).reduce((s, w) => s + w.balance, 0),
    ...totals(current),
    previousIncome: previous.income,
    previousExpense: previous.expense,
    wallets,
    expenseByCategory,
    budgets: state.budgets
      .filter((b) => b.currency === currency && L.sameMonth(L.monthValue(b.month), month))
      .map((b) => ({ ...b, used: L.used(state, b) })),
    debt: {
      payable: L.outstanding(state, { borrowed: true, currency }),
      receivable: L.outstanding(state, { borrowed: false, currency }),
    },
    recent: state.entries.filter(inCurrency(state, currency)).sort(byNewest).slice(0, 5),
  };
}

async function summary(user, query) {
  const state = await ledger.loadState(user._id);
  const currency = currencyOf(user, query);
  const now = new Date();
  const from = L.date(query.from, 'from') || L.monthStart(now);
  const to = L.date(query.to, 'to') || L.monthEnd(now);
  const groupBy = query.groupBy === 'month' ? 'month' : 'day';
  const list = state.entries.filter((e) => {
    const d = new Date(e.date);
    return !e.excluded && inCurrency(state, currency)(e) && d >= from && d <= to;
  });
  const periodOf = (d) => {
    const month = `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
    return groupBy === 'month' ? month : `${month}-${pad(d.getDate())}`;
  };
  const series = {};
  for (const e of list) {
    const period = periodOf(new Date(e.date));
    series[period] ??= { period, income: 0, expense: 0 };
    if (isIncome(e.kind)) series[period].income += e.amount;
    if (isExpense(e.kind)) series[period].expense += e.amount;
  }
  const byCategory = state.categories
    .map((c) => ({
      categoryId: c.id,
      name: c.name,
      income: c.income,
      amount: sum(list.filter((e) => e.categoryId === c.id && (c.income ? isIncome(e.kind) : isExpense(e.kind)))),
    }))
    .filter((x) => x.amount > 0)
    .sort((a, b) => b.amount - a.amount);
  return {
    currency,
    from: from.toISOString(),
    to: to.toISOString(),
    groupBy,
    ...totals(list),
    series: Object.values(series).sort((a, b) => a.period.localeCompare(b.period)),
    byCategory,
  };
}

async function debts(user, query) {
  const state = await ledger.loadState(user._id);
  const currency = currencyOf(user, query);
  const people = state.people
    .map((p) => ({
      personId: p.id,
      name: p.name,
      payable: L.outstanding(state, { borrowed: true, personId: p.id, currency }),
      receivable: L.outstanding(state, { borrowed: false, personId: p.id, currency }),
      entries: state.entries.filter((e) => isDebt(e.kind) && e.personId === p.id && inCurrency(state, currency)(e)),
    }))
    .filter((p) => p.entries.length > 0);
  return { currency, people };
}

module.exports = { dashboard, summary, debts };
