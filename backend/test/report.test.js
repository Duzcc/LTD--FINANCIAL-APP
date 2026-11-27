const { test } = require('node:test');
const assert = require('node:assert/strict');
const ledger = require('../src/services/ledger.service');
const reports = require('../src/services/report.service');

test('Báo cáo tháng khớp với các giao dịch thu chi trong tháng', async (t) => {
  const first = new Date(2026, 10, 1);
  const last = new Date(2026, 10, 30, 23, 59, 59, 999);
  const expense = { kind: 'expense', categoryId: 'food', walletId: 'cash', date: first };
  const income = { kind: 'income', categoryId: 'salary', walletId: 'cash', date: last };
  const state = {
    wallets: [
      { id: 'cash', currency: 'VND', opening: 0 },
      { id: 'usd', currency: 'USD', opening: 0 },
    ],
    categories: [
      { id: 'food', name: 'Ăn uống', income: false },
      { id: 'salary', name: 'Lương', income: true },
    ],
    budgets: [],
    entries: [
      { ...expense, amount: 45000 },
      { ...expense, amount: 30000, date: last },
      { ...income, amount: 200000 },
      { ...income, kind: 'interestIncome', amount: 5000 },
      { ...expense, amount: 10000, excluded: true },
      { ...expense, amount: 20, walletId: 'usd' },
      { ...expense, amount: 90000, kind: 'transfer' },
      { ...income, amount: 60000, kind: 'borrow' },
      { ...expense, amount: 40000, date: new Date(2026, 9, 31) },
      { ...expense, amount: 15000, date: new Date(2026, 11, 1) },
    ],
  };
  t.mock.method(ledger, 'loadState', async () => state);

  const user = { currency: 'VND' };
  const dashboard = await reports.dashboard(user, { month: '2026-11' });
  const report = await reports.summary(user, { from: first, to: last });

  for (const result of [dashboard, report]) {
    assert.equal(result.income, 205000);
    assert.equal(result.expense, 75000);
  }
  assert.equal(dashboard.previousExpense, 40000);
  assert.deepEqual(
    report.series.map(({ income, expense }) => [income, expense]),
    [
      [0, 45000],
      [205000, 30000],
    ],
  );
  assert.deepEqual(
    report.byCategory.map(({ categoryId, amount }) => [categoryId, amount]),
    [
      ['salary', 205000],
      ['food', 75000],
    ],
  );
});
