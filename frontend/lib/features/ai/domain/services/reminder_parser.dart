import 'package:finance_app/features/finance/domain/entities/spending_reminder.dart';
import 'package:finance_app/features/ai/domain/services/category_model.dart';

class ReminderDraft {
  const ReminderDraft(this.title, this.at, this.repeat);
  final String title;
  final DateTime at;
  final ReminderRepeat repeat;
}

class ReminderParser {
  ReminderParser({DateTime? now}) : now = now ?? DateTime.now();
  final DateTime now;

  static final _intent = RegExp(r'^(hay )?nhac (toi|minh|em|giup|ho|nho)\b|^nhac nho\b|\bnhac (toi|minh) (la|ve)?');

  static bool matches(String text) => _intent.hasMatch(foldVietnamese(text));

  static final _prefix = RegExp(r'^\s*(hãy\s+)?nhắc(\s+nhở)?((\s+(tôi|mình|em|giúp|hộ))+)?(\s+(là|về))?\s*:?\s*',
      caseSensitive: false);
  static final _noise = [
    RegExp(r'\b(vào\s+|lúc\s+)*\d{1,2}\s*(h(?![a-zà-ỹ])|giờ|:)\s*(\d{2})?\s*(phút)?(\s+(sáng|trưa|chiều|tối))?',
        caseSensitive: false),
    RegExp(r'\b(vào\s+)?(ngày\s+mai|hôm\s+nay|cuối\s+tháng|chủ\s+nhật|thứ\s+[2-7])\b', caseSensitive: false),
    RegExp(r'\b(vào\s+)?ngày\s+\d{1,2}(\s*/\s*\d{1,2})?', caseSensitive: false),
    RegExp(r'\b(hằng|hàng|mỗi)\s+(ngày|tuần|tháng)\b', caseSensitive: false),
    RegExp(r'\b\d+\s+ngày\s+(nữa|tới)\b', caseSensitive: false),
    RegExp(r'\b(sáng|trưa|chiều|tối)\s+(mai|nay)\b', caseSensitive: false),
  ];

  ReminderDraft? parse(String text) {
    if (!matches(text)) return null;
    final f = foldVietnamese(text);
    final repeat = RegExp(r'\b(hang|moi) ngay\b').hasMatch(f)
        ? ReminderRepeat.daily
        : RegExp(r'\b(hang|moi) tuan\b').hasMatch(f)
            ? ReminderRepeat.weekly
            : RegExp(r'\b(hang|moi) thang\b').hasMatch(f)
                ? ReminderRepeat.monthly
                : ReminderRepeat.none;

    var hour = 9, minute = 0;
    var hasTime = false;
    final time = RegExp(r'(?<!\d)(\d{1,2})\s*(?:h(?![a-zà-ỹ])|giờ|:)\s*(\d{2})?(?!\d)').firstMatch(text.toLowerCase());
    if (time != null) {
      final h = int.parse(time[1]!), m = int.tryParse(time[2] ?? '') ?? 0;
      if (h < 24 && m < 60) {
        hour = h;
        minute = m;
        hasTime = true;
      }
    }
    final evening = RegExp(r'(?<![a-zà-ỹ])(chiều|tối)(?![a-zà-ỹ])').hasMatch(text.toLowerCase());
    if (hasTime && evening && hour < 12) hour += 12;
    if (!hasTime && evening) hour = 20;

    final today = DateTime(now.year, now.month, now.day);
    var day = today;
    var explicitDay = false;
    final dayOfMonth = RegExp(r'\bngay (\d{1,2})(?: (\d{1,2}))?\b').firstMatch(f);
    final weekday = RegExp(r'\b(thu ([2-7])|chu nhat)\b').firstMatch(f);
    final later = RegExp(r'\b(\d+) ngay (nua|toi)\b').firstMatch(f);
    if (RegExp(r'\b(ngay|sang|trua|chieu|toi) mai\b').hasMatch(f)) {
      day = today.add(const Duration(days: 1));
      explicitDay = true;
    } else if (later != null) {
      day = today.add(Duration(days: int.parse(later[1]!)));
      explicitDay = true;
    } else if (RegExp(r'\bcuoi thang\b').hasMatch(f)) {
      day = DateTime(now.year, now.month + 1, 0);
      explicitDay = true;
    } else if (dayOfMonth != null && int.parse(dayOfMonth[1]!) >= 1 && int.parse(dayOfMonth[1]!) <= 31) {
      final d = int.parse(dayOfMonth[1]!);
      final m = int.tryParse(dayOfMonth[2] ?? '');
      day = DateTime(now.year, m ?? now.month, d);
      if (day.isBefore(today)) day = m == null ? DateTime(now.year, now.month + 1, d) : DateTime(now.year + 1, m, d);
      explicitDay = true;
    } else if (weekday != null) {
      final target = weekday[2] == null ? DateTime.sunday : int.parse(weekday[2]!) - 1;
      day = today.add(Duration(days: (target - today.weekday + 7) % 7));
      explicitDay = true;
    }
    var at = DateTime(day.year, day.month, day.day, hour, minute);
    if (!at.isAfter(now) && !explicitDay) at = at.add(const Duration(days: 1));
    if (!at.isAfter(now) && repeat == ReminderRepeat.none) at = at.add(const Duration(days: 7));

    var title = text.replaceFirst(_prefix, '');
    for (final r in _noise) {
      title = title.replaceAll(r, ' ');
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[\s,.:\-]+|[\s,.:\-]+$'), '');
    if (title.isEmpty) title = 'Kiểm tra chi tiêu';
    return ReminderDraft(title[0].toUpperCase() + title.substring(1), at, repeat);
  }
}
