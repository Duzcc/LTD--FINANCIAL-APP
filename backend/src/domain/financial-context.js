const L = require('./ledger');
const { isIncome, isExpense, isDebt } = require('./constants');

const sum = (list) => list.reduce((s, e) => s + e.amount, 0);
const round = (v) => Math.round(v);

function financialContext(state, user, now = new Date()) {
  const cur = user.currency || 'VND';
  const inCurrency = (e) => L.byId(state.wallets, e.walletId)?.currency === cur;
  const monthOf = (offset) => new Date(now.getFullYear(), now.getMonth() - offset, 1);
  const months = [0, 1, 2, 3].map((i) => {
    const m = monthOf(i);
    const list = state.entries.filter((e) => !e.excluded && inCurrency(e) && L.sameMonth(new Date(e.date), m));
    return {
      month: `${m.getMonth() + 1}/${m.getFullYear()}`,
      income: round(sum(list.filter((e) => isIncome(e.kind)))),
      expense: round(sum(list.filter((e) => isExpense(e.kind)))),
      byCategory: state.categories
        .map((c) => ({ name: c.name, amount: round(sum(list.filter((e) => e.categoryId === c.id && (c.income ? isIncome(e.kind) : isExpense(e.kind))))) }))
        .filter((x) => x.amount > 0)
        .sort((a, b) => b.amount - a.amount)
        .slice(0, 8),
    };
  });
  const thisMonth = monthOf(0);
  return {
    today: now.toISOString().slice(0, 10),
    dayOfMonth: now.getDate(),
    daysInMonth: new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate(),
    currency: cur,
    wallets: state.wallets.map((w) => ({
      name: w.name,
      type: w.savings ? 'tiết kiệm' : 'cơ bản',
      currency: w.currency,
      balance: round(L.balance(state, w.id)),
      target: w.target || undefined,
    })),
    months,
    budgets: state.budgets.filter((b) => L.sameMonth(L.monthValue(b.month), thisMonth)).map((b) => ({
      category: b.categoryId ? L.byId(state.categories, b.categoryId)?.name : (b.income ? 'Mục tiêu thu cả tháng' : 'Tổng chi cả tháng'),
      limit: round(b.amount),
      used: round(L.used(state, b)),
    })),
    debts: state.people.map((p) => ({
      person: p.name,
      theyOweMe: round(L.outstanding(state, { borrowed: false, personId: p.id, currency: cur })),
      iOwe: round(L.outstanding(state, { borrowed: true, personId: p.id, currency: cur })),
      nextDue: state.entries
        .filter((e) => isDebt(e.kind) && e.personId === p.id && e.dueDate)
        .map((e) => new Date(e.dueDate).toISOString().slice(0, 10))
        .sort()[0],
    })).filter((d) => d.theyOweMe > 0 || d.iOwe > 0),
    recurring: (state.recurring || []).filter((r) => r.active).map((r) => ({ note: r.note, amount: r.amount, frequency: r.frequency })),
  };
}

function rulesReply(context) {
  const m = context.months[0];
  const money = (v) => `${v.toLocaleString('vi-VN')} ${context.currency}`;
  return `Tháng ${m.month}: thu ${money(m.income)}, chi ${money(m.expense)}. Máy chủ chưa cấu hình mô hình AI nên câu trả lời chi tiết được tạo trên thiết bị.`;
}

module.exports = { financialContext, rulesReply };
