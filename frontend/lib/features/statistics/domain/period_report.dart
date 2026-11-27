import 'package:finance_app/features/finance/domain/entities/entities.dart';

// Tổng thu chi trong một kỳ
class CashTotals {
  double income = 0;
  double expense = 0;

  void add(MoneyEntry entry) {
    if (entry.kind.isIncome) {
      income += entry.amount;
    } else if (entry.kind.isExpense) {
      expense += entry.amount;
    }
  }
}

class PeriodReport {
  PeriodReport({
    required DateTime from,
    required DateTime until,
    required Iterable<MoneyEntry> entries,
  }) {
    final last = DateTime(until.year, until.month, until.day - 1);
    final months = (last.year - from.year) * 12 + last.month - from.month + 1;
    final daily = !last.isAfter(DateTime(from.year, from.month, from.day + 30));
    final yearly = months > 24;

    DateTime bucket(DateTime date) {
      if (daily) return DateTime(date.year, date.month, date.day);
      if (yearly) return DateTime(date.year);
      return DateTime(date.year, date.month);
    }

    var date = bucket(from);
    while (date.isBefore(until)) {
      series[date] = CashTotals();
      if (daily) {
        labels.add(months == 1 ? '${date.day}' : '${date.day}/${date.month}');
        date = DateTime(date.year, date.month, date.day + 1);
      } else if (yearly) {
        labels.add('${date.year}');
        date = DateTime(date.year + 1);
      } else {
        labels.add(from.year == last.year
            ? 'T${date.month}'
            : '${date.month}/${date.year % 100}');
        date = DateTime(date.year, date.month + 1);
      }
    }

    for (final entry in entries) {
      if (entry.date.isBefore(from) || !entry.date.isBefore(until)) continue;
      if (entry.excluded || (!entry.kind.isIncome && !entry.kind.isExpense)) continue;

      totals.add(entry);
      series[bucket(entry.date)]!.add(entry);
      final amounts = entry.kind.isIncome ? incomeByCategory : expenseByCategory;
      final id = entry.categoryId;
      amounts[id] = (amounts[id] ?? 0) + entry.amount;
    }
  }

  final totals = CashTotals();
  final series = <DateTime, CashTotals>{};
  final labels = <String>[];
  final incomeByCategory = <String?, double>{};
  final expenseByCategory = <String?, double>{};
}
