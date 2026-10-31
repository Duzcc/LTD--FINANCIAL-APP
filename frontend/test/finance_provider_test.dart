import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';

void main() {
  final month = DateTime(2026, 10);
  MoneyEntry entry(String id, EntryKind kind, double amount,
          {String wallet = 'cash',
          String? dest,
          String? category,
          bool excluded = false,
          DateTime? date,
          String? person}) =>
      MoneyEntry(
        id: id,
        kind: kind,
        amount: amount,
        walletId: wallet,
        destinationId: dest,
        categoryId: category ?? (kind.isIncome ? 'salary' : 'food'),
        date: date ?? month,
        excluded: excluded,
        personId: person,
      );
  test('Create, edit, move and delete an entry recomputes balances and budget',
      () async {
    final p = FinanceProvider();
    p.saveWallet(
        const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 1000000));
    p.saveWallet(
        const MoneyWallet(id: 'bank', name: 'Ngân hàng', opening: 500000));
    p.saveBudget(MoneyBudget(
        id: 'budget',
        categoryId: 'food',
        month: month,
        amount: 200000,
        walletId: 'cash'));
    p.saveEntry(entry('a', EntryKind.expense, 50000));
    expect(p.balance('cash'), 950000);
    expect(p.used(p.budgets.single), 50000);
    p.saveEntry(entry('a', EntryKind.expense, 80000, wallet: 'bank'));
    expect(p.balance('cash'), 1000000);
    expect(p.balance('bank'), 420000);
    expect(p.used(p.budgets.single), 0);
    expect(p.total(month, income: false), 80000);
    p.deleteEntry('a');
    expect(p.balance('bank'), 500000);
    expect(p.total(month, income: false), 0);
    await p.flush();
    p.dispose();
  });
  test('Transfer changes both wallets and is excluded from income and expense',
      () async {
    final p = FinanceProvider();
    p.saveWallet(
        const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 1000000));
    p.saveWallet(
        const MoneyWallet(id: 'saving', name: 'Tiết kiệm', savings: true));
    p.saveEntry(entry('t', EntryKind.transfer, 200000, dest: 'saving'));
    expect(p.balance('cash'), 800000);
    expect(p.balance('saving'), 200000);
    expect(p.totalBalance('VND'), 1000000);
    expect(p.total(month, income: false), 0);
    expect(p.total(month, income: true), 0);
    p.deleteEntry('t');
    expect(p.balance('cash'), 1000000);
    expect(p.balance('saving'), 0);
    expect(() => p.saveEntry(entry('x', EntryKind.transfer, 1, dest: 'cash')),
        throwsArgumentError);
    p.saveWallet(const MoneyWallet(id: 'usd', name: 'Dollar', currency: 'USD'));
    expect(() => p.saveEntry(entry('x', EntryKind.transfer, 1, dest: 'usd')),
        throwsArgumentError);
    await p.flush();
    p.dispose();
  });
  test('Debt principals and interest have different report behavior', () async {
    final p = FinanceProvider();
    p.savePerson(const MoneyPerson('a', 'An', 'Bạn bè'));
    p.saveEntry(entry('b', EntryKind.borrow, 1000, person: 'a'));
    p.saveEntry(entry('r', EntryKind.repay, 200, person: 'a'));
    p.saveEntry(entry('i', EntryKind.interestExpense, 50, person: 'a'));
    p.saveEntry(entry('l', EntryKind.lend, 100, person: 'a'));
    p.saveEntry(entry('c', EntryKind.collect, 30, person: 'a'));
    expect(p.balance('cash'), 680);
    expect(p.debt(borrowed: true, personId: 'a'), 800);
    expect(p.debt(borrowed: false, personId: 'a'), 70);
    expect(p.total(month, income: false), 50);
    expect(p.total(month, income: true), 0);
    expect(() => p.saveEntry(entry('invalid', EntryKind.borrow, 5)),
        throwsArgumentError);
    await p.flush();
    p.dispose();
  });
  test('Months, currencies and report exclusions do not mix', () async {
    final p = FinanceProvider();
    p.saveWallet(const MoneyWallet(
        id: 'usd', name: 'USD', currency: 'USD', opening: 100));
    p.saveEntry(entry('one', EntryKind.expense, 5, wallet: 'usd'));
    p.saveEntry(entry('two', EntryKind.expense, 100));
    p.saveEntry(entry('hidden', EntryKind.expense, 20, excluded: true));
    p.saveEntry(
        entry('last', EntryKind.expense, 50, date: DateTime(2026, 9, 30)));
    p.saveEntry(
        entry('31', EntryKind.income, 200, date: DateTime(2026, 10, 31)));
    expect(p.total(month, income: false), 100);
    expect(p.total(month, income: false, unit: 'USD'), 5);
    expect(p.total(month, income: true), 200);
    expect(p.balance('cash'), 30);
    expect(p.totalBalance('USD'), 95);
    expect(() => p.deleteWallet('usd'), throwsArgumentError);
    expect(() => p.deleteCategory('food'), throwsArgumentError);
    expect(() => p.saveEntry(entry('zero', EntryKind.expense, 0)),
        throwsArgumentError);
    expect(() => p.saveEntry(entry('nan', EntryKind.expense, double.nan)),
        throwsArgumentError);
    await p.flush();
    p.dispose();
  });
  test('Data survives reload including edits, preferences and deletions',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final p = FinanceProvider(storage: storage);
    p.preferences(name: 'Đức', unit: 'VND', hidden: true);
    p.saveWallet(MoneyWallet(
        id: 'saving',
        name: 'Laptop',
        savings: true,
        target: 20000000,
        deadline: DateTime(2027)));
    p.saveEntry(entry('one', EntryKind.income, 300000));
    p.saveEntry(entry('two', EntryKind.expense, 50000));
    p.deleteEntry('two');
    p.saveBudget(
        MoneyBudget(id: 'b', categoryId: 'food', month: month, amount: 200000));
    await p.flush();
    final restored = FinanceProvider(storage: storage)..restore();
    expect(restored.entries.length, 1);
    expect(restored.balance('cash'), 300000);
    expect(restored.wallet('saving').target, 20000000);
    expect(restored.budgets.single.amount, 200000);
    expect(restored.displayName, 'Đức');
    expect(restored.hideBalance, true);
    p.dispose();
    restored.dispose();
  });
  test('Wallet rules: duplicate names, savings dates and cascade delete',
      () async {
    final p = FinanceProvider();
    p.saveWallet(const MoneyWallet(id: 'bank', name: 'Ngân hàng'));
    expect(() => p.saveWallet(const MoneyWallet(id: 'x', name: ' ngân HÀNG ')),
        throwsArgumentError);
    expect(
        () => p.saveWallet(MoneyWallet(
            id: 's',
            name: 'Heo đất',
            savings: true,
            startDate: DateTime(2026, 10, 10),
            deadline: DateTime(2026, 10, 1))),
        throwsArgumentError);
    p.saveWallet(const MoneyWallet(id: 'saving', name: 'Tiết kiệm', savings: true));
    p.saveEntry(entry('t', EntryKind.transfer, 100, dest: 'saving'));
    p.saveEntry(entry('e', EntryKind.expense, 50, wallet: 'saving'));
    expect(p.totalBalance('VND'), -50);
    expect(p.totalBalance('VND', spendableOnly: true), -100);
    expect(p.walletReferences('saving'), 2);
    expect(() => p.deleteWallet('saving'), throwsArgumentError);
    p.deleteWallet('saving', cascade: true);
    expect(p.entries, isEmpty);
    expect(p.balance('cash'), 0);
    await p.flush();
    p.dispose();
  });
  test('Repayments cannot exceed the outstanding debt per person', () async {
    final p = FinanceProvider();
    p.savePerson(const MoneyPerson('a', 'An', 'Bạn bè'));
    p.savePerson(const MoneyPerson('b', 'Bình', 'Bạn bè'));
    expect(() => p.saveEntry(entry('c0', EntryKind.collect, 10, person: 'a')),
        throwsArgumentError);
    p.saveEntry(entry('l', EntryKind.lend, 100, person: 'a'));
    expect(() => p.saveEntry(entry('c1', EntryKind.collect, 120, person: 'a')),
        throwsArgumentError);
    expect(() => p.saveEntry(entry('c2', EntryKind.collect, 10, person: 'b')),
        throwsArgumentError);
    p.saveEntry(entry('c3', EntryKind.collect, 100, person: 'a'));
    // Sửa chính giao dịch thu nợ: không tính lại phần của chính nó.
    p.saveEntry(entry('c3', EntryKind.collect, 60, person: 'a'));
    final t = p.debtTotals(borrowed: false);
    expect(t.principal, 100);
    expect(t.settled, 60);
    expect(p.debt(borrowed: false, personId: 'a'), 40);
    await p.flush();
    p.dispose();
  });
  test('Monthly overall target, category budgets and copying', () async {
    final p = FinanceProvider();
    p.saveBudget(MoneyBudget(
        id: 'all', categoryId: null, month: month, amount: 1000000));
    expect(
        () => p.saveBudget(MoneyBudget(
            id: 'all2', categoryId: null, month: month, amount: 5)),
        throwsArgumentError);
    p.saveBudget(MoneyBudget(
        id: 'goal', categoryId: null, month: month, amount: 9, income: true));
    p.saveBudget(
        MoneyBudget(id: 'food', categoryId: 'food', month: month, amount: 300));
    p.saveEntry(entry('a', EntryKind.expense, 200));
    p.saveEntry(entry('b', EntryKind.expense, 50, category: 'house'));
    p.saveEntry(entry('c', EntryKind.income, 7));
    expect(p.used(p.overallBudget(month, income: false)!), 250);
    expect(p.used(p.overallBudget(month, income: true)!), 7);
    expect(p.used(p.budgets.firstWhere((b) => b.id == 'food')), 200);
    final next = DateTime(2026, 11);
    expect(p.copyBudgets(month, next), 3);
    expect(p.copyBudgets(month, next), 0);
    expect(p.overallBudget(next, income: false)!.amount, 1000000);
    await p.flush();
    p.dispose();
  });
}
