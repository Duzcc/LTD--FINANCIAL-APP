import 'package:finance_app/core/utils/json_fields.dart';
import 'package:finance_app/features/finance/domain/entities/entry_kind.dart';

enum RepeatFrequency {
  daily('Hằng ngày', 'ngày'),
  weekly('Hằng tuần', 'tuần'),
  monthly('Hằng tháng', 'tháng'),
  yearly('Hằng năm', 'năm');

  const RepeatFrequency(this.label, this.unit);
  final String label, unit;
}

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

  final DateTime? nextDate;
  final bool active;

  DateTime get upcoming => nextDate ?? startDate;

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
        'startDate': isoUtc(startDate),
        'endDate': isoUtc(endDate),
        'nextDate': isoUtc(nextDate),
        'active': active,
      };
  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
      id: j['id'],
      kind: EntryKind.values.byName(j['kind']),
      amount: parseNumber(j['amount']),
      walletId: j['walletId'],
      destinationId: j['destinationId'],
      categoryId: j['categoryId'],
      personId: j['personId'],
      note: j['note'] ?? '',
      frequency: RepeatFrequency.values.byName(j['frequency'] ?? 'monthly'),
      interval: parseNumber(j['interval'] ?? 1).toInt().clamp(1, 365),
      startDate: parseLocalDate(j['startDate'])!,
      endDate: parseLocalDate(j['endDate']),
      nextDate: parseLocalDate(j['nextDate']),
      active: j['active'] != false);
}
