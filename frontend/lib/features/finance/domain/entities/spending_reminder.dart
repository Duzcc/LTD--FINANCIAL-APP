import 'package:finance_app/core/utils/json_fields.dart';

enum ReminderRepeat {
  none('Một lần'),
  daily('Hằng ngày'),
  weekly('Hằng tuần'),
  monthly('Hằng tháng');

  const ReminderRepeat(this.label);
  final String label;
}

class SpendingReminder {
  const SpendingReminder({required this.id, required this.title, required this.at, this.repeat = ReminderRepeat.none});
  final String id, title;
  final DateTime at;
  final ReminderRepeat repeat;

  DateTime nextAfter(DateTime now) {
    var next = at;
    var step = 0;
    while (!next.isAfter(now) && repeat != ReminderRepeat.none) {
      step++;
      next = switch (repeat) {
        ReminderRepeat.daily => DateTime(at.year, at.month, at.day + step, at.hour, at.minute),
        ReminderRepeat.weekly => DateTime(at.year, at.month, at.day + 7 * step, at.hour, at.minute),
        _ => _monthly(step),
      };
    }
    return next;
  }

  DateTime _monthly(int step) {
    final first = DateTime(at.year, at.month + step);
    final last = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, at.day > last ? last : at.day, at.hour, at.minute);
  }

  bool expired(DateTime now) => repeat == ReminderRepeat.none && !at.isAfter(now);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'at': isoUtc(at), 'repeat': repeat.name};

  factory SpendingReminder.fromJson(Map<String, dynamic> j) => SpendingReminder(
      id: j['id'],
      title: j['title'] ?? '',
      at: parseLocalDate(j['at'])!,
      repeat: ReminderRepeat.values.where((r) => r.name == j['repeat']).firstOrNull ?? ReminderRepeat.none);
}
