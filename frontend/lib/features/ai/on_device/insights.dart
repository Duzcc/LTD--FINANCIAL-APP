import 'dart:math' as math;
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/ai/data/ai_models.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';

enum InsightLevel { good, info, warning, danger }

class Insight {
  const Insight(this.level, this.title, this.detail, {this.categoryId});
  final InsightLevel level;
  final String title, detail;
  final String? categoryId;
}

/// Dự báo chi tiêu cuối tháng.
class SpendForecast {
  const SpendForecast(
      {required this.spent,
      required this.projected,
      required this.dailyAverage,
      required this.daysLeft,
      this.target});
  final double spent, projected, dailyAverage;
  final int daysLeft;
  final double? target;
  bool get overBudget => target != null && projected > target!;
}

/// Phân tích tài chính trên thiết bị: dự báo, phát hiện bất thường,
/// nhịp chi ngân sách, khoản chi lặp lại, tỷ lệ tiết kiệm.
class FinanceInsights {
  FinanceInsights(this.p, {DateTime? now, this.server}) : now = now ?? DateTime.now();
  final FinanceProvider p;
  final DateTime now;

  /// Dự báo của AI service (nếu có) — ưu tiên dùng để mọi màn hình hiển thị cùng một con số.
  final ForecastResult? server;

  String _m(double v) {
    final s = v.round().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    return p.currency == 'VND' ? '$s ₫' : '$s ${p.currency}';
  }

  DateTime get _monthStart => DateTime(now.year, now.month);
  int get _daysInMonth => DateTime(now.year, now.month + 1, 0).day;

  /// Dự báo = đã chi + (trung bình/ngày kết hợp tháng này và 3 tháng trước) × số ngày còn lại.
  SpendForecast forecast() {
    final srv = server;
    if (srv != null) {
      return SpendForecast(
          spent: srv.spent,
          projected: srv.projected,
          dailyAverage: srv.daysLeft > 0 ? ((srv.projected - srv.spent) / srv.daysLeft).roundToDouble() : 0,
          daysLeft: srv.daysLeft,
          target: p.overallBudget(now, income: false)?.amount);
    }
    final spent = p.total(now, income: false);
    final elapsed = now.day;
    final daysLeft = _daysInMonth - elapsed;
    final thisDaily = spent / elapsed;
    var history = 0.0, months = 0;
    for (var i = 1; i <= 3; i++) {
      final m = DateTime(now.year, now.month - i);
      final v = p.total(m, income: false);
      if (v > 0) {
        history += v / DateTime(m.year, m.month + 1, 0).day;
        months++;
      }
    }
    final histDaily = months == 0 ? thisDaily : history / months;
    // Đầu tháng tin vào lịch sử nhiều hơn, cuối tháng tin vào tháng hiện tại.
    final w = math.min(1.0, elapsed / 15);
    final daily = w * thisDaily + (1 - w) * histDaily;
    final target = p.overallBudget(now, income: false)?.amount;
    return SpendForecast(
        spent: spent,
        projected: (spent + daily * daysLeft).roundToDouble(),
        dailyAverage: daily.roundToDouble(),
        daysLeft: daysLeft,
        target: target);
  }

  /// Có dữ liệu chi tiêu ở ít nhất một trong 3 tháng trước không.
  bool get _hasHistory => [1, 2, 3].any((i) => p.total(DateTime(now.year, now.month - i), income: false) > 0);

  List<Insight> all() {
    final out = <Insight>[];
    final f = forecast();
    if (f.spent > 0 && server == null && !_hasHistory && now.day < 3) {
      // Mới vài ngày dữ liệu và chưa có tháng trước: nhân thẳng ra cả tháng dễ sai lệch lớn.
      out.add(Insight(InsightLevel.info, 'Đang học thói quen chi tiêu của bạn',
          'Cần thêm vài ngày ghi chép để dự báo cuối tháng chính xác. Đến nay bạn đã chi ${_m(f.spent)}.'));
    } else if (f.spent > 0) {
      if (f.overBudget) {
        out.add(Insight(
            InsightLevel.danger,
            'Dự kiến vượt ngân sách tháng',
            'Với tốc độ hiện tại (${_m(f.dailyAverage)}/ngày), tháng này bạn sẽ chi khoảng ${_m(f.projected)}, vượt mục tiêu ${_m(f.target!)} khoảng ${_m(f.projected - f.target!)}.'));
      } else {
        out.add(Insight(
            InsightLevel.info,
            'Dự báo chi tiêu cuối tháng: ${_m(f.projected)}',
            f.target == null
                ? 'Trung bình ${_m(f.dailyAverage)}/ngày, còn ${f.daysLeft} ngày. Hãy đặt mục tiêu tháng để được cảnh báo sớm.'
                : 'Nằm trong mục tiêu ${_m(f.target!)}; bạn còn dư khoảng ${_m(f.target! - f.projected)}.'));
      }
    }

    // Danh mục chi tăng bất thường so với trung bình 3 tháng trước (đã quy về cùng số ngày).
    final ratio = now.day / _daysInMonth;
    for (final c in p.categories.where((c) => !c.income)) {
      final current = p.total(now, income: false, categoryId: c.id);
      if (current <= 0) continue;
      var sum = 0.0, n = 0;
      for (var i = 1; i <= 3; i++) {
        final v = p.total(DateTime(now.year, now.month - i), income: false, categoryId: c.id);
        if (v > 0) {
          sum += v;
          n++;
        }
      }
      if (n == 0) continue;
      final expected = sum / n * ratio;
      if (expected > 0 && current > expected * 1.5 && current - expected > 100000) {
        out.add(Insight(
            InsightLevel.warning,
            '${c.name} tăng ${((current / expected - 1) * 100).round()}%',
            'Từ đầu tháng bạn đã chi ${_m(current)} cho ${c.name}, trong khi cùng kỳ các tháng trước trung bình ${_m(expected)}.',
            categoryId: c.id));
      }
    }

    // Ngân sách danh mục đang tiêu nhanh hơn thời gian trôi qua.
    for (final b in p.budgets.where((b) =>
        b.categoryId != null &&
        !p.budgetIncome(b) &&
        b.currency == p.currency &&
        b.month.year == now.year &&
        b.month.month == now.month)) {
      final used = p.used(b) / b.amount;
      final name = p.category(b.categoryId)?.name ?? '';
      if (used > 1) {
        out.add(Insight(InsightLevel.danger, 'Đã vượt ngân sách $name',
            'Đã dùng ${(used * 100).round()}% hạn mức ${_m(b.amount)}.',
            categoryId: b.categoryId));
      } else if (used > ratio + .2 && used > .5) {
        out.add(Insight(
            InsightLevel.warning,
            'Ngân sách $name đang tiêu nhanh',
            'Đã dùng ${(used * 100).round()}% hạn mức trong khi mới qua ${(ratio * 100).round()}% tháng. Có thể chi tối đa ${_m((b.amount - p.used(b)) / math.max(1, _daysInMonth - now.day))}/ngày.',
            categoryId: b.categoryId));
      }
    }

    // Khoản chi lớn bất thường trong 30 ngày (lớn hơn trung bình + 3 độ lệch chuẩn của 90 ngày).
    final recent = p.between(now.subtract(const Duration(days: 90)), now.add(const Duration(days: 1)), unit: p.currency)
        .where((e) => e.kind.isExpense && !e.excluded)
        .toList();
    if (recent.length >= 8) {
      final mean = recent.fold(0.0, (s, e) => s + e.amount) / recent.length;
      final sd = math.sqrt(recent.fold(0.0, (s, e) => s + math.pow(e.amount - mean, 2)) / recent.length);
      for (final e in recent.where((e) =>
          e.date.isAfter(now.subtract(const Duration(days: 30))) && e.amount > mean + 3 * sd)) {
        out.add(Insight(
            InsightLevel.info,
            'Khoản chi lớn: ${_m(e.amount)}',
            '${p.category(e.categoryId)?.name ?? e.kind.label}${e.note.isEmpty ? '' : ' – ${e.note}'} ngày ${e.date.day}/${e.date.month}, cao hơn nhiều so với mức thường ngày (${_m(mean)}).',
            categoryId: e.categoryId));
      }
    }

    // Khoản chi lặp lại hằng tháng chưa được đặt định kỳ.
    for (final s in subscriptions()) {
      out.add(Insight(InsightLevel.info, 'Có vẻ là khoản cố định: ${s.$1}',
          'Khoảng ${_m(s.$2)} lặp lại ${s.$3} tháng gần đây. Bạn có thể tạo giao dịch định kỳ để ghi tự động.'));
    }

    // Tỷ lệ tiết kiệm.
    final income = p.total(now, income: true), expense = p.total(now, income: false);
    if (income > 0) {
      final rate = (income - expense) / income;
      out.add(Insight(
          rate >= .2 ? InsightLevel.good : rate >= 0 ? InsightLevel.info : InsightLevel.danger,
          'Tỷ lệ tiết kiệm tháng này: ${(rate * 100).round()}%',
          rate >= .2
              ? 'Rất tốt! Bạn đang để dành hơn 20% thu nhập.'
              : rate >= 0
                  ? 'Mục tiêu phổ biến là để dành 20% thu nhập (quy tắc 50/30/20).'
                  : 'Chi tiêu đang vượt thu nhập ${_m(expense - income)}.'));
    }
    const order = [InsightLevel.danger, InsightLevel.warning, InsightLevel.info, InsightLevel.good];
    out.sort((a, b) => order.indexOf(a.level).compareTo(order.indexOf(b.level)));
    return out;
  }

  /// (ghi chú, số tiền trung bình, số tháng) của khoản chi xuất hiện ≥ 2 trong 3 tháng gần nhất.
  List<(String, double, int)> subscriptions() {
    final groups = <String, List<MoneyEntry>>{};
    final from = DateTime(now.year, now.month - 3);
    for (final e in p.between(from, now.add(const Duration(days: 1)), unit: p.currency)) {
      if (!e.kind.isExpense || e.note.trim().isEmpty || e.recurringId != null) continue;
      groups.putIfAbsent(foldVietnamese(e.note), () => []).add(e);
    }
    final result = <(String, double, int)>[];
    final covered = p.recurring.map((r) => foldVietnamese(r.note)).toSet();
    groups.forEach((key, list) {
      if (covered.contains(key)) return;
      final months = list.map((e) => e.date.year * 12 + e.date.month).toSet().length;
      if (months < 2) return;
      final avg = list.fold(0.0, (s, e) => s + e.amount) / list.length;
      final similar = list.every((e) => (e.amount - avg).abs() <= avg * .15);
      if (similar) result.add((list.first.note, avg, months));
    });
    return result.take(3).toList();
  }

  // Dùng cho trợ lý: thống kê nhanh.
  Map<String, Object> summary() {
    final f = forecast();
    final byCat = [
      for (final c in p.categories.where((c) => !c.income))
        (c.name, p.total(now, income: false, categoryId: c.id))
    ].where((x) => x.$2 > 0).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return {
      'month': '${now.month}/${now.year}',
      'currency': p.currency,
      'balance': p.totalBalance(p.currency),
      'income': p.total(now, income: true),
      'expense': f.spent,
      'forecast': f.projected,
      'target': f.target ?? 0,
      'topCategories': byCat.take(5).map((e) => '${e.$1}: ${_m(e.$2)}').toList(),
      'receivable': p.debt(borrowed: false),
      'payable': p.debt(borrowed: true),
      'monthStart': _monthStart.toIso8601String(),
    };
  }
}
