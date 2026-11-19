import 'package:finance_app/features/finance/domain/entities/entities.dart';

typedef DebtTotals = ({double principal, double settled});

mixin LedgerQueries {
  List<MoneyWallet> get wallets;
  List<MoneyEntry> get entries;
  List<MoneyCategory> get categories;
  List<MoneyPerson> get people;
  List<MoneyBudget> get budgets;
  List<RecurringRule> get recurring;
  String get currency;
  Map<String, double> get rates;

  MoneyWallet wallet(String id) => wallets.firstWhere((w) => w.id == id);

  MoneyWallet? findWallet(String? id) {
    for (final w in wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  MoneyCategory? category(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String personName(String? id) {
    for (final p in people) {
      if (p.id == id) return p.name;
    }
    return '';
  }

  String _unitOf(MoneyEntry e) => findWallet(e.walletId)?.currency ?? '';

  double convert(double value, String from, String to) =>
      from == to ? value : value * (rates[from] ?? 1) / (rates[to] ?? 1);

  bool get hasManyCurrencies => wallets.map((w) => w.currency).toSet().length > 1;

  double balance(String id) => entries.fold(
      wallet(id).opening,
      (sum, e) =>
          sum +
          (e.walletId == id ? e.amount * e.kind.sign : 0) +
          (e.kind == EntryKind.transfer && e.destinationId == id ? e.amount : 0));

  Iterable<MoneyWallet> _counted({bool spendableOnly = false}) =>
      wallets.where((w) => !w.excluded && (!spendableOnly || !w.savings));

  double totalBalance(String unit, {bool spendableOnly = false}) =>
      _counted(spendableOnly: spendableOnly).where((w) => w.currency == unit).fold(0, (sum, w) => sum + balance(w.id));

  double convertedTotal(String unit, {bool spendableOnly = false}) =>
      _counted(spendableOnly: spendableOnly).fold(0, (sum, w) => sum + convert(balance(w.id), w.currency, unit));

  int walletReferences(String id) =>
      entries.where((e) => e.walletId == id || e.destinationId == id).length +
      budgets.where((b) => b.walletId == id).length +
      recurring.where((r) => r.walletId == id || r.destinationId == id).length;

  List<MoneyEntry> between(DateTime from, DateTime to, {String? walletId, String? unit}) => entries
      .where((e) =>
          !e.date.isBefore(from) &&
          e.date.isBefore(to) &&
          (walletId == null || e.walletId == walletId || e.destinationId == walletId) &&
          (unit == null || _unitOf(e) == unit))
      .toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  List<MoneyEntry> inMonth(DateTime month, {String? walletId, String? unit}) =>
      between(DateTime(month.year, month.month), DateTime(month.year, month.month + 1), walletId: walletId, unit: unit);

  double sumBetween(DateTime from, DateTime to,
          {required bool income, String? walletId, String? categoryId, String? unit}) =>
      between(from, to, walletId: walletId, unit: unit ?? currency)
          .where((e) =>
              !e.excluded &&
              (walletId == null || e.walletId == walletId) &&
              (income ? e.kind.isIncome : e.kind.isExpense) &&
              (categoryId == null || e.categoryId == categoryId))
          .fold(0, (s, e) => s + e.amount);

  double total(DateTime month, {required bool income, String? walletId, String? categoryId, String? unit}) =>
      sumBetween(DateTime(month.year, month.month), DateTime(month.year, month.month + 1),
          income: income, walletId: walletId, categoryId: categoryId, unit: unit);

  bool budgetIncome(MoneyBudget b) => b.categoryId == null ? b.income : category(b.categoryId)?.income ?? false;

  double used(MoneyBudget b) =>
      total(b.month, income: budgetIncome(b), walletId: b.walletId, categoryId: b.categoryId, unit: b.currency);

  MoneyBudget? overallBudget(DateTime month, {required bool income, String? unit}) {
    for (final b in budgets) {
      if (b.categoryId == null &&
          b.income == income &&
          b.currency == (unit ?? currency) &&
          b.month.year == month.year &&
          b.month.month == month.month) {
        return b;
      }
    }
    return null;
  }

  double debt({required bool borrowed, String? personId, String? unit, String? excludeId}) {
    final totals = debtTotals(borrowed: borrowed, personId: personId, unit: unit, excludeId: excludeId);
    return totals.principal - totals.settled;
  }

  DebtTotals debtTotals({required bool borrowed, String? personId, String? unit, String? excludeId}) {
    final principalKind = borrowed ? EntryKind.borrow : EntryKind.lend;
    final settleKind = borrowed ? EntryKind.repay : EntryKind.collect;
    var principal = 0.0, settled = 0.0;
    for (final e in entries) {
      if (e.id == excludeId) continue;
      if (personId != null && e.personId != personId) continue;
      if (_unitOf(e) != (unit ?? currency)) continue;
      if (e.kind == principalKind) principal += e.amount;
      if (e.kind == settleKind) settled += e.amount;
    }
    return (principal: principal, settled: settled);
  }
}
