import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/domain/ledger_queries.dart';

class SpendingAllowance {
  const SpendingAllowance(
      {required this.limit,
      required this.fromBudget,
      required this.daily,
      required this.spentToday,
      required this.daysLeft});
  final double limit, daily, spentToday;
  final bool fromBudget;
  final int daysLeft;
  double get leftToday => daily - spentToday;
}

class SpendingCoach {
  SpendingCoach(this.p, {DateTime? now, this.reminders = const []}) : now = now ?? DateTime.now();
  final LedgerQueries p;
  final DateTime now;
  final List<SpendingReminder> reminders;

  DateTime get _today => DateTime(now.year, now.month, now.day);

  String _m(double v) {
    final s = v.abs().round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    return '${v < 0 ? '-' : ''}$s ${p.currency == 'VND' ? '₫' : p.currency}';
  }

  SpendingAllowance? allowance() {
    final budget = p.overallBudget(now, income: false);
    var limit = budget?.amount;
    if (limit == null) {
      var income = p.total(now, income: true);
      if (income <= 0) income = p.total(DateTime(now.year, now.month - 1), income: true);
      if (income > 0) limit = income * .8;
    }
    if (limit == null) return null;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final spentToday = p.sumBetween(_today, _today.add(const Duration(days: 1)), income: false);
    final before = p.sumBetween(DateTime(now.year, now.month), _today, income: false);
    final daily = ((limit - before).clamp(0, double.infinity) / daysLeft).roundToDouble();
    return SpendingAllowance(
        limit: limit, fromBudget: budget != null, daily: daily, spentToday: spentToday, daysLeft: daysLeft);
  }

  String allowanceText() {
    final a = allowance();
    if (a == null) {
      return 'Mình chưa có ngân sách tổng hay thu nhập tháng này để tính mức chi mỗi ngày. '
          'Hãy đặt ngân sách tổng tháng ở mục Ngân sách nhé.';
    }
    return [
      'Theo ${a.fromBudget ? 'ngân sách tổng' : 'thu nhập sau khi để dành 20%'} (${_m(a.limit)}), '
          'từ nay đến cuối tháng bạn nên chi tối đa ${_m(a.daily)}/ngày.',
      'Hôm nay đã chi ${_m(a.spentToday)}, ${a.leftToday >= 0 ? 'còn ${_m(a.leftToday)}' : 'vượt ${_m(-a.leftToday)}'}.',
      for (final line in _tightBudgets()) '• $line',
    ].join('\n');
  }

  List<String> _tightBudgets() {
    final progress = now.day / DateTime(now.year, now.month + 1, 0).day;
    final out = <String>[];
    for (final b in p.budgets) {
      if (b.categoryId == null || b.month.year != now.year || b.month.month != now.month || p.budgetIncome(b)) continue;
      final used = p.used(b);
      final name = p.category(b.categoryId)?.name ?? 'Danh mục';
      if (used > b.amount) {
        out.add('$name đã vượt ngân sách ${_m(used - b.amount)}');
      } else if (b.amount > 0 && used / b.amount > progress + .1) {
        out.add('$name đã dùng ${(used / b.amount * 100).round()}% ngân sách, còn ${_m(b.amount - used)}');
      }
    }
    return out;
  }

  List<String> budgetWarnings(Set<String> categoryIds) {
    final out = <String>[];
    for (final b in p.budgets) {
      if (b.month.year != now.year || b.month.month != now.month || p.budgetIncome(b) || b.amount <= 0) continue;
      if (b.categoryId != null && !categoryIds.contains(b.categoryId)) continue;
      final used = p.used(b);
      final name = b.categoryId == null ? 'Tổng chi' : p.category(b.categoryId)?.name ?? 'Danh mục';
      if (used > b.amount) {
        out.add('Ngân sách $name đã vượt ${_m(used - b.amount)}.');
      } else if (used / b.amount >= .8) {
        out.add('Ngân sách $name đã dùng ${(used / b.amount * 100).round()}%, còn ${_m(b.amount - used)}.');
      }
    }
    return out;
  }

  List<String> alerts() {
    final out = <String>[];
    final a = allowance();
    if (a != null && a.spentToday > a.daily && a.daily > 0) {
      out.add('Hôm nay bạn đã chi ${_m(a.spentToday)}, quá mức gợi ý ${_m(a.daily)}/ngày.');
    }
    out.addAll(_tightBudgets().take(2));
    final soon = _today.add(const Duration(days: 4));
    for (final e in p.entries) {
      final due = e.dueDate;
      if (due == null || due.isBefore(_today) || !due.isBefore(soon)) continue;
      if (e.kind != EntryKind.lend && e.kind != EntryKind.borrow) continue;
      if (p.debt(borrowed: e.kind == EntryKind.borrow, personId: e.personId) <= 0) continue;
      final days = DateTime(due.year, due.month, due.day).difference(_today).inDays;
      final when = days == 0
          ? 'hôm nay'
          : days == 1
              ? 'ngày mai'
              : 'sau $days ngày';
      out.add(e.kind == EntryKind.lend
          ? 'Khoản cho ${p.personName(e.personId)} vay đến hạn thu $when.'
          : 'Khoản vay của ${p.personName(e.personId)} đến hạn trả $when.');
    }
    for (final r in reminders) {
      final next = r.nextAfter(now);
      if (!r.expired(now) && next.isBefore(_today.add(const Duration(days: 2)))) {
        out.add('Nhắc nhở ${next.day == now.day ? 'hôm nay' : 'ngày mai'} ${_hm(next)}: ${r.title}.');
      }
    }
    return out;
  }

  String _hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  String greeting(String name) {
    final items = alerts();
    final a = allowance();
    return [
      'Chào $name! Mình có thể gợi ý mức chi, tìm lại giao dịch, đặt nhắc nhở, '
          'hoặc đọc hóa đơn bạn chụp và ghi từng món vào đúng danh mục.',
      if (a != null && items.isEmpty) 'Hôm nay bạn còn có thể chi khoảng ${_m(a.leftToday.clamp(0, double.infinity))}.',
      if (items.isNotEmpty) 'Cần chú ý:\n${items.take(4).map((e) => '• $e').join('\n')}',
    ].join('\n\n');
  }
}
