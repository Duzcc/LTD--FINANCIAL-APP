import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';

/// Kết quả phân tích một câu nhập nhanh.
class ParsedEntry {
  ParsedEntry(
      {required this.kind,
      required this.amount,
      required this.date,
      required this.note,
      this.categoryId,
      this.personId,
      this.newPersonName,
      this.walletId,
      this.confidence = 0});
  final EntryKind kind;
  final double? amount;
  final DateTime date;
  final String note;
  final String? categoryId, personId, newPersonName, walletId;

  /// Độ tin cậy 0–1 của việc nhận dạng (dựa trên số thành phần tìm được).
  final double confidence;
}

/// Bộ phân tích câu tiếng Việt tự nhiên thành giao dịch, chạy trên thiết bị:
/// "ăn phở 45k sáng nay", "lương tháng 12tr", "cho An mượn 500 nghìn",
/// "hôm qua đổ xăng 70.000 bằng thẻ", "trả nợ Bình 1tr2".
class QuickEntryParser {
  QuickEntryParser(this.p);
  final FinanceProvider p;

  static final _amount = RegExp(
      r'(\d+(?:[.,]\d+)*)\s*(k|nghin|ngan|ng|tr|trieu|cu|ty|ti|d|dong|vnd)?(\d{1,3})?\b');

  /// Đọc số tiền từ chuỗi đã bỏ dấu. "1tr2" = 1.200.000; "45k" = 45.000;
  /// "1,5tr" = 1.500.000; "200.000" = 200.000; "phở 45" = 45.000.
  /// Ưu tiên con số có đơn vị (k, tr…) nếu câu có nhiều số.
  static (double, int, int)? findAmount(String folded) {
    (double, int, int)? unitless;
    for (final m in _amount.allMatches(folded)) {
      final raw = m.group(1)!;
      final unit = m.group(2);
      final tail = m.group(3);
      final before = folded.substring(0, m.start);
      if (unit == null && RegExp(r'(ngay|thang|luc|gio)\s*$').hasMatch(before)) continue;
      if (m.end < folded.length && folded[m.end] == '/') continue;
      if (m.start > 0 && folded[m.start - 1] == '/') continue;
      if (unit == null || unit == 'd' || unit == 'dong' || unit == 'vnd') {
        final grouped = RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(raw);
        var value = double.tryParse(grouped
                ? raw.replaceAll(RegExp(r'[.,]'), '')
                : raw.replaceAll(',', '.')) ??
            0;
        if (unit == null && value < 1000) value *= 1000;
        if (value <= 0) continue;
        if (unit != null || grouped) return (value, m.start, m.end);
        unitless ??= (value, m.start, m.end);
        continue;
      }
      final base = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
      final mult = switch (unit) {
        'k' || 'nghin' || 'ngan' || 'ng' => 1e3,
        'tr' || 'trieu' || 'cu' => 1e6,
        _ => 1e9,
      };
      var value = base * mult;
      if (tail != null) {
        // "1tr2" = 1,2 triệu; "1tr250" = 1,25 triệu; "1ty5" = 1,5 tỷ.
        value += double.parse('0.$tail') * mult;
      }
      if (value > 0) return (value, m.start, m.end);
    }
    return unitless;
  }

  static DateTime _dateFrom(String f, DateTime now) {
    var date = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (RegExp(r'\bhom kia\b').hasMatch(f)) {
      date = date.subtract(const Duration(days: 2));
    } else if (RegExp(r'\b(hom qua|toi qua|dem qua|trua qua|sang qua|chieu qua)\b').hasMatch(f)) {
      date = date.subtract(const Duration(days: 1));
    } else {
      final dm = RegExp(r'\b(\d{1,2})\s*/\s*(\d{1,2})(?:\s*/\s*(\d{2,4}))?\b').firstMatch(f);
      final day = RegExp(r'\bngay\s+(\d{1,2})\b').firstMatch(f);
      if (dm != null) {
        final d = int.parse(dm.group(1)!), m = int.parse(dm.group(2)!);
        var y = dm.group(3) == null ? now.year : int.parse(dm.group(3)!);
        if (y < 100) y += 2000;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          date = DateTime(y, m, d, 12);
          if (dm.group(3) == null && date.isAfter(now.add(const Duration(days: 1)))) {
            date = DateTime(y - 1, m, d, 12);
          }
        }
      } else if (day != null) {
        final d = int.parse(day.group(1)!);
        if (d >= 1 && d <= 31) {
          date = DateTime(now.year, now.month, d, 12);
          if (date.isAfter(now.add(const Duration(days: 1)))) {
            date = DateTime(now.year, now.month - 1, d, 12);
          }
        }
      }
    }
    final hour = RegExp(r'\bsang\b').hasMatch(f)
        ? 8
        : RegExp(r'\btrua\b').hasMatch(f)
            ? 12
            : RegExp(r'\bchieu\b').hasMatch(f)
                ? 16
                : RegExp(r'\b(toi|dem)\b').hasMatch(f)
                    ? 20
                    : null;
    if (hour != null) date = DateTime(date.year, date.month, date.day, hour);
    return date;
  }

  /// Lấy lại tên có dấu từ câu gốc tương ứng với tên đã bỏ dấu [folded].
  static String _originalName(String text, String folded) {
    final original = text
        .split(RegExp(r'[^0-9A-Za-zÀ-ỹĐđ]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final parts = folded.split(' ');
    for (var i = 0; i + parts.length <= original.length; i++) {
      var ok = true;
      for (var j = 0; j < parts.length; j++) {
        if (foldVietnamese(original[i + j]) != parts[j]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return original
            .sublist(i, i + parts.length)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
      }
    }
    return folded;
  }

  ParsedEntry parse(String text, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final f = foldKeepNumbers(text);
    final found = findAmount(f);
    var score = found == null ? 0.0 : .4;

    // Đối tượng: tên đã có trong danh sách xuất hiện trong câu.
    String? personId;
    final people = [...p.people]..sort((a, b) => b.name.length.compareTo(a.name.length));
    for (final person in people) {
      final n = foldVietnamese(person.name);
      if (n.isNotEmpty && person.id != 'self' && RegExp('\\b${RegExp.escape(n)}\\b').hasMatch(f)) {
        personId = person.id;
        break;
      }
    }

    // Loại giao dịch theo từ khóa.
    EntryKind kind;
    String? newName;
    final lend = RegExp(r'\bcho\s+([a-z]+(?:\s[a-z]+)?)\s+(muon|vay)\b').firstMatch(f);
    final borrow = RegExp(r'\b(muon|vay)\s+(?:cua\s+|tien\s+)?([a-z]+)\b').firstMatch(f);
    final repay = RegExp(r'\btra\s+(?:no\s+|tien\s+)?(?:cho\s+)?([a-z]+)\b').firstMatch(f);
    final collect = RegExp(r'\b(thu no|doi no)\s+([a-z]+)\b|\b([a-z]+)\s+tra\s+(?:no|tien)\b').firstMatch(f);
    const pronouns = {'toi', 'minh', 'em', 'anh', 'chi', 'tao', 'da', 'di', 'phai'};
    final collectMatch =
        collect != null && !pronouns.contains(collect.group(3)) ? collect : null;
    if (RegExp(r'\btra lai\b').hasMatch(f)) {
      kind = EntryKind.interestExpense;
    } else if (RegExp(r'\b(thu lai|tien lai|lai tiet kiem)\b').hasMatch(f)) {
      kind = EntryKind.interestIncome;
    } else if (lend != null) {
      kind = EntryKind.lend;
      newName = lend.group(1);
    } else if (collectMatch != null) {
      kind = EntryKind.collect;
      newName = collectMatch.group(2) ?? collectMatch.group(3);
    } else if (RegExp(r'\btra no\b').hasMatch(f) && repay != null) {
      kind = EntryKind.repay;
      newName = repay.group(1);
    } else if (borrow != null && !RegExp(r'\bcho\b').hasMatch(f)) {
      kind = EntryKind.borrow;
      newName = borrow.group(2);
    } else if (RegExp(r'\b(chuyen|nap)\s+(tien\s+)?(vao|sang|qua)\b').hasMatch(f)) {
      kind = EntryKind.transfer;
    } else if (RegExp(r'\b(luong|thuong|nhan|duoc cho|duoc tang|ban do|ban hang|thu nhap|hoan tien|li xi|lam them)\b').hasMatch(f)) {
      kind = EntryKind.income;
    } else {
      kind = EntryKind.expense;
    }
    // So sánh theo chữ gốc có dấu: "Minh" là tên người, còn "mình" là đại từ.
    const stop = {'nợ', 'tiền', 'cho', 'của', 'lãi', 'mình', 'tôi', 'em', 'anh', 'chị', 'bạn', 'tao', 'nó'};
    final original = newName == null ? null : _originalName(text, newName).toLowerCase();
    if (personId == null && kind.isDebt && newName != null && !stop.contains(original)) {
      final existing = p.people.where((x) => foldVietnamese(x.name) == newName).firstOrNull;
      personId = existing?.id;
      if (existing != null) newName = null;
    } else {
      newName = null;
    }
    if (kind != EntryKind.expense) score += .2;

    // Ví: tên ví xuất hiện trong câu, hoặc "thẻ/ngân hàng/chuyển khoản".
    String? walletId;
    for (final w in p.wallets) {
      final n = foldVietnamese(w.name);
      if (n.isNotEmpty && f.contains(n)) {
        walletId = w.id;
        break;
      }
    }
    if (walletId == null && RegExp(r'\b(the|ngan hang|chuyen khoan|ck|bank)\b').hasMatch(f)) {
      walletId = p.wallets.where((w) => !w.savings && w.id != 'cash').firstOrNull?.id;
    }
    walletId ??= p.wallets.firstOrNull?.id;

    // Ghi chú: câu gốc bỏ phần số tiền.
    var note = text.trim();
    if (found != null) {
      final words = text.trim().split(RegExp(r'\s+'));
      final kept = words.where((w) => findAmount(foldKeepNumbers(w)) == null || RegExp(r'^\d{1,2}/\d{1,2}').hasMatch(w));
      note = kept.join(' ');
    }
    note = note.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (note.isNotEmpty) note = note[0].toUpperCase() + note.substring(1);

    String? categoryId;
    if (kind.isIncome || kind.isExpense) {
      final model = p.cached(() => CategoryModel.train(p.categories, p.entries));
      categoryId = model.suggest(note.isEmpty ? text : note, income: kind.isIncome, minProbability: .2) ??
          p.categories.where((c) => c.income == kind.isIncome).firstOrNull?.id;
      score += .2;
    }
    if (personId != null || !kind.isDebt) score += .2;
    return ParsedEntry(
        kind: kind,
        amount: found?.$1,
        date: _dateFrom(f, t),
        note: note,
        categoryId: categoryId,
        personId: personId,
        newPersonName: newName == null ? null : _originalName(text, newName),
        walletId: walletId,
        confidence: score.clamp(0, 1));
  }
}
