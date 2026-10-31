import 'package:flutter/material.dart';

enum EntryKind {
  expense('Chi tiêu', -1),
  income('Thu nhập', 1),
  transfer('Chuyển tiền', -1),
  lend('Cho vay', -1),
  collect('Thu nợ', 1),
  interestIncome('Thu lãi', 1),
  borrow('Đi vay', 1),
  repay('Trả nợ', -1),
  interestExpense('Trả lãi', -1);

  const EntryKind(this.label, this.sign);
  final String label;
  final int sign;
  bool get isDebt => index >= 3;
  bool get isIncome => this == income || this == interestIncome;
  bool get isExpense => this == expense || this == interestExpense;
}

class MoneyWallet {
  const MoneyWallet(
      {required this.id,
      required this.name,
      this.opening = 0,
      this.currency = 'VND',
      this.savings = false,
      this.excluded = false,
      this.target = 0,
      this.startDate,
      this.deadline});
  final String id, name, currency;
  final double opening, target;
  final bool savings, excluded;
  final DateTime? startDate, deadline;
  IconData get icon =>
      savings ? Icons.savings_outlined : Icons.account_balance_wallet_outlined;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'opening': opening,
        'currency': currency,
        'savings': savings,
        'excluded': excluded,
        'target': target,
        'startDate': _iso(startDate),
        'deadline': _iso(deadline)
      };
  factory MoneyWallet.fromJson(Map<String, dynamic> j) => MoneyWallet(
      id: j['id'],
      name: j['name'],
      opening: _number(j['opening']),
      currency: j['currency'] ?? 'VND',
      savings: j['savings'] == true,
      excluded: j['excluded'] == true,
      target: _number(j['target']),
      startDate: _date(j['startDate']),
      deadline: _date(j['deadline']));
}

class MoneyEntry {
  const MoneyEntry(
      {required this.id,
      required this.kind,
      required this.amount,
      required this.walletId,
      required this.date,
      this.destinationId,
      this.categoryId,
      this.personId,
      this.note = '',
      this.dueDate,
      this.excluded = false,
      this.photo,
      this.recurringId});
  final String id, walletId, note;
  final String? destinationId, categoryId, personId;

  /// Đường dẫn ảnh hóa đơn trên thiết bị (không đồng bộ lên máy chủ).
  final String? photo;

  /// Giao dịch được sinh từ quy tắc định kỳ nào (nếu có).
  final String? recurringId;
  MoneyEntry copyWith({String? photo, bool clearPhoto = false}) => MoneyEntry(
      id: id,
      kind: kind,
      amount: amount,
      walletId: walletId,
      date: date,
      destinationId: destinationId,
      categoryId: categoryId,
      personId: personId,
      note: note,
      dueDate: dueDate,
      excluded: excluded,
      photo: clearPhoto ? null : photo ?? this.photo,
      recurringId: recurringId);
  final EntryKind kind;
  final double amount;
  final DateTime date;
  final DateTime? dueDate;
  final bool excluded;
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'walletId': walletId,
        'date': _iso(date),
        'destinationId': destinationId,
        'categoryId': categoryId,
        'personId': personId,
        'note': note,
        'dueDate': _iso(dueDate),
        'excluded': excluded,
        'photo': photo,
        'recurringId': recurringId
      };
  factory MoneyEntry.fromJson(Map<String, dynamic> j) => MoneyEntry(
      id: j['id'],
      kind: EntryKind.values.byName(j['kind']),
      amount: _number(j['amount']),
      walletId: j['walletId'],
      date: _date(j['date'])!,
      destinationId: j['destinationId'],
      categoryId: j['categoryId'],
      personId: j['personId'],
      note: j['note'] ?? '',
      dueDate: _date(j['dueDate']),
      excluded: j['excluded'] == true,
      photo: j['photo'],
      recurringId: j['recurringId']);
}

enum RepeatFrequency {
  daily('Hằng ngày', 'ngày'),
  weekly('Hằng tuần', 'tuần'),
  monthly('Hằng tháng', 'tháng'),
  yearly('Hằng năm', 'năm');

  const RepeatFrequency(this.label, this.unit);
  final String label, unit;
}

/// Quy tắc giao dịch định kỳ: tiền nhà, lương, gói cước, nạp tiết kiệm…
/// Mỗi lần đến hạn, ứng dụng sinh một giao dịch có mã cố định
/// "<mã quy tắc>_r<yyyymmdd>" nên không bị trùng khi đồng bộ nhiều thiết bị.
class RecurringRule {
  const RecurringRule(
      {required this.id,
      required this.kind,
      required this.amount,
      required this.walletId,
      required this.frequency,
      required this.startDate,
      this.interval = 1,
      this.endDate,
      this.nextDate,
      this.destinationId,
      this.categoryId,
      this.personId,
      this.note = '',
      this.active = true});
  final String id, walletId, note;
  final String? destinationId, categoryId, personId;
  final EntryKind kind;
  final double amount;
  final RepeatFrequency frequency;
  final int interval;
  final DateTime startDate;
  final DateTime? endDate;

  /// Lần đến hạn kế tiếp chưa được sinh giao dịch (null = bắt đầu từ startDate).
  final DateTime? nextDate;
  final bool active;

  DateTime get upcoming => nextDate ?? startDate;

  /// Ngày đến hạn thứ [n] (n = 0 là ngày bắt đầu). Tháng thiếu ngày được lùi về cuối tháng.
  DateTime occurrence(int n) {
    final s = startDate;
    switch (frequency) {
      case RepeatFrequency.daily:
        return DateTime(s.year, s.month, s.day + n * interval, s.hour, s.minute);
      case RepeatFrequency.weekly:
        return DateTime(
            s.year, s.month, s.day + 7 * n * interval, s.hour, s.minute);
      case RepeatFrequency.monthly:
      case RepeatFrequency.yearly:
        final months =
            n * interval * (frequency == RepeatFrequency.yearly ? 12 : 1);
        final first = DateTime(s.year, s.month + months);
        final last = DateTime(first.year, first.month + 1, 0).day;
        return DateTime(first.year, first.month, s.day > last ? last : s.day,
            s.hour, s.minute);
    }
  }

  /// Lần đến hạn đầu tiên sau [after].
  DateTime nextAfter(DateTime after) {
    var n = 0;
    while (!occurrence(n).isAfter(after) && n < 100000) {
      n++;
    }
    return occurrence(n);
  }

  String occurrenceId(DateTime d) =>
      '${id}_r${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  String get describe =>
      interval == 1 ? frequency.label : 'Mỗi $interval ${frequency.unit}';

  RecurringRule copyWith({DateTime? nextDate, bool? active}) => RecurringRule(
      id: id,
      kind: kind,
      amount: amount,
      walletId: walletId,
      frequency: frequency,
      startDate: startDate,
      interval: interval,
      endDate: endDate,
      nextDate: nextDate ?? this.nextDate,
      destinationId: destinationId,
      categoryId: categoryId,
      personId: personId,
      note: note,
      active: active ?? this.active);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'walletId': walletId,
        'destinationId': destinationId,
        'categoryId': categoryId,
        'personId': personId,
        'note': note,
        'frequency': frequency.name,
        'interval': interval,
        'startDate': _iso(startDate),
        'endDate': _iso(endDate),
        'nextDate': _iso(nextDate),
        'active': active,
      };
  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
      id: j['id'],
      kind: EntryKind.values.byName(j['kind']),
      amount: _number(j['amount']),
      walletId: j['walletId'],
      destinationId: j['destinationId'],
      categoryId: j['categoryId'],
      personId: j['personId'],
      note: j['note'] ?? '',
      frequency: RepeatFrequency.values.byName(j['frequency'] ?? 'monthly'),
      interval: _number(j['interval'] ?? 1).toInt().clamp(1, 365),
      startDate: _date(j['startDate'])!,
      endDate: _date(j['endDate']),
      nextDate: _date(j['nextDate']),
      active: j['active'] != false);
}

class MoneyCategory {
  const MoneyCategory(this.id, this.name, this.income, this.symbol);
  final String id, name;
  final bool income;
  final int symbol;
  static const icons = [
    Icons.restaurant_outlined,
    Icons.water_drop_outlined,
    Icons.home_outlined,
    Icons.checkroom_outlined,
    Icons.directions_car_outlined,
    Icons.medical_services_outlined,
    Icons.child_care_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.card_giftcard_outlined,
    Icons.trending_up,
    Icons.savings_outlined,
    Icons.business_center_outlined,
    Icons.volunteer_activism_outlined,
    Icons.category_outlined,
    Icons.local_cafe_outlined,
    Icons.shopping_cart_outlined,
    Icons.school_outlined,
    Icons.sports_esports_outlined,
    Icons.flight_outlined,
    Icons.pets_outlined,
    Icons.phone_iphone_outlined,
    Icons.receipt_long_outlined,
    Icons.fitness_center_outlined,
    Icons.attach_money
  ];
  IconData get icon => icons[symbol.clamp(0, icons.length - 1)];
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'income': income, 'symbol': symbol};
  factory MoneyCategory.fromJson(Map<String, dynamic> j) => MoneyCategory(
      j['id'], j['name'], j['income'] == true, _number(j['symbol']).toInt());
}

class MoneyPerson {
  const MoneyPerson(this.id, this.name, this.group);
  final String id, name, group;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'group': group};
  factory MoneyPerson.fromJson(Map<String, dynamic> j) =>
      MoneyPerson(j['id'], j['name'], j['group'] ?? 'Cá nhân');
}

/// Ngân sách theo tháng. [categoryId] == null là mục tiêu tổng của cả tháng
/// (chi tiêu khi [income] = false, thu nhập khi [income] = true).
class MoneyBudget {
  const MoneyBudget(
      {required this.id,
      required this.categoryId,
      required this.month,
      required this.amount,
      this.walletId,
      this.currency = 'VND',
      this.income = false});
  final String id, currency;
  final String? categoryId, walletId;
  final DateTime month;
  final double amount;
  final bool income;
  bool get isOverall => categoryId == null;
  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'month':
            '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
        'amount': amount,
        'walletId': walletId,
        'currency': currency,
        'income': income
      };
  factory MoneyBudget.fromJson(Map<String, dynamic> j) {
    final m = _date(j['month'])!;
    return MoneyBudget(
        id: j['id'],
        categoryId: j['categoryId'],
        month: DateTime(m.year, m.month),
        amount: _number(j['amount']),
        walletId: j['walletId'],
        currency: j['currency'] ?? 'VND',
        income: j['income'] == true);
  }
}

/// Thời điểm gửi lên máy chủ/lưu trữ luôn kèm múi giờ (UTC) để không bị lệch giờ.
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

double _number(Object? v) => v is num
    ? v.toDouble()
    : v is String
        ? double.tryParse(v) ?? 0
        : 0;

/// Ngày từ máy chủ ở dạng UTC được đổi về giờ máy để so sánh theo ngày/tháng.
DateTime? _date(Object? v) {
  if (v == null || v == '') return null;
  final d = DateTime.tryParse(v.toString());
  return d?.isUtc == true ? d!.toLocal() : d;
}
