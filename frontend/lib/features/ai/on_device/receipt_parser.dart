import 'dart:math' as math;

/// Phân tích văn bản hóa đơn tiếng Việt sau OCR (chạy trên thiết bị, không cần mạng).
///
/// Cùng thuật toán với AI service (`ai-service/app/services/receipt/parser.py`):
/// sửa lỗi OCR trong số, so khớp từ khóa đã bỏ dấu (chịu lỗi 1 ký tự), rồi "bỏ phiếu"
/// tổng tiền giữa các nguồn độc lập: dòng TỔNG, tiền khách đưa − tiền thừa,
/// tổng tiền hàng − giảm giá, tổng các dòng hàng.
class ReceiptLineItem {
  const ReceiptLineItem(this.name, this.amount);
  final String name;
  final double amount;
}

class ParsedReceipt {
  ParsedReceipt({this.merchant, this.total, this.date, this.items = const [], this.confidence = 0, this.checks = const []});
  final String? merchant;
  final double? total;
  final DateTime? date;
  final List<ReceiptLineItem> items;
  final double confidence;
  final List<String> checks;

  String get note => merchant != null && items.isNotEmpty
      ? '$merchant: ${items.take(3).map((i) => i.name).join(', ')}'
      : merchant ?? items.take(3).map((i) => i.name).join(', ');
}

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Chữ thường, bỏ dấu, sửa "0" kẹp giữa chữ cái thành "o" (T0NG C0NG).
String receiptKey(String line) {
  final b = StringBuffer();
  for (final ch in line.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString().replaceAllMapped(RegExp(r'(?<=[a-z])0|0(?=[a-z])'), (_) => 'o');
}

const _totalKeys = <(String, int)>[
  ('tong thanh toan', 0), ('tong tien thanh toan', 0), ('khach phai tra', 0), ('khach can tra', 0),
  ('can thanh toan', 0), ('phai thanh toan', 0), ('grand total', 0), ('amount due', 0),
  ('tong cong', 1), ('thanh toan', 1), ('total', 1), ('phai tra', 1),
  ('tong tien', 2), ('tong', 3), ('cong', 4),
];
const _subtotal = ['tong tien hang', 'tam tinh', 'subtotal', 'cong tien hang', 'tien hang'];
const _cash = ['tien khach dua', 'khach dua', 'tien nhan', 'khach tra', 'cash', 'tien mat'];
const _change = ['tien thua', 'tien thoi', 'thoi lai', 'tra lai khach', 'tien tra lai', 'change'];
const _notItem = ['giam gia', 'chiet khau', 'discount', 'vat', 'thue', 'khuyen mai', 'phi dich vu', 'service'];
const _discount = ['giam gia', 'chiet khau', 'khuyen mai', 'discount'];
const _header = ['ten hang', 'don gia', 'thanh tien', 't.tien', 'd.gia', 'sl ', 'mat hang', 'so luong'];
const _notMerchant = ['dia chi', 'dc:', 'd/c', 'dt:', 'dt ', 'tel', 'hotline', 'mst', 'ma so thue', 'hoa don',
  'phieu', 'so hd', 'ngay', 'thu ngan', 'nhan vien', 'ban hang', 'www', 'http'];
const knownMerchants = ['circle k', 'winmart', 'bach hoa xanh', 'highlands', 'phuc long', 'co.opmart', 'coopmart',
  'co.op', '7-eleven', 'gs25', 'familymart', 'ministop', 'lotte', 'aeon', 'big c', 'go!', 'mm mega', 'kfc',
  'lotteria', 'jollibee', 'pharmacity', 'long chau', 'an khang', 'the coffee house', 'starbucks', 'katinat',
  'guardian', 'dien may xanh', 'the gioi di dong', 'fahasa', 'uniqlo', 'pho thin', 'gong cha'];

final _num = RegExp(r'(?<![\w.,])(\d{1,3}(?:[.,]\d{3})+|\d{4,9})(?:[.,]0{1,2})?\s*(?:đ|d|vnd|vnđ|dong)?(?![\w])',
    caseSensitive: false);

/// Sửa lỗi OCR trong các cụm trông giống số tiền: "1O5.OOO" → "105.000", "46. 000" → "46.000".
String cleanOcrNumbers(String line) {
  const map = {'O': '0', 'o': '0', 'D': '0', 'l': '1', 'I': '1', '|': '1', 'S': '5', 'B': '8', 'Z': '2'};
  var out = line.replaceAllMapped(RegExp(r'[0-9OolI|SBZD][0-9OolI|SBZD.,]{2,}[0-9OolI|SBZD]'), (m) {
    final tok = m[0]!;
    if (!tok.contains(RegExp(r'\d'))) return tok;
    final fixed = tok.split('').map((c) => map[c] ?? c).join();
    return RegExp(r'^(\d{1,3}(?:[.,]\d{3})+|\d{4,})$').hasMatch(fixed) ? fixed : tok;
  });
  out = out.replaceAllMapped(RegExp(r'(\d)\s+([.,])\s*(\d{3})(?!\d)'), (m) => '${m[1]}${m[2]}${m[3]}');
  out = out.replaceAllMapped(RegExp(r'(\d)([.,])\s+(\d{3})(?!\d)'), (m) => '${m[1]}${m[2]}${m[3]}');
  out = out.replaceAllMapped(RegExp(r'(?<![\d.,])(\d{1,3}) (\d{3})(?![\d.,]| ?x)'), (m) => '${m[1]}.${m[2]}');
  return out;
}

List<double> receiptAmounts(String line) {
  final out = <double>[];
  for (final m in _num.allMatches(line)) {
    final raw = m[1]!;
    final grouped = RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(raw);
    if (!grouped && raw.length >= 9) continue; // số điện thoại, mã số
    final v = double.parse(raw.replaceAll(RegExp(r'[.,]'), ''));
    if (v >= 500 && v <= 5e9) out.add(v);
  }
  return out;
}

/// Độ giống 0..1 theo khoảng cách Levenshtein — chịu được lỗi OCR 1–2 ký tự.
double _similarity(String a, String b) {
  if (a == b) return 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return 1 - prev[b.length] / math.max(a.length, b.length);
}

bool _has(String f, List<String> keys, {bool fuzzy = false}) {
  if (keys.any(f.contains)) return true;
  if (!fuzzy) return false;
  final words = f.split(RegExp(r'\s+'));
  for (final k in keys) {
    final n = k.split(' ').length;
    if (k.length < 7) continue;
    for (var i = 0; i + n <= words.length; i++) {
      if (_similarity(words.sublist(i, i + n).join(' '), k) >= 0.8) return true;
    }
  }
  return false;
}

DateTime? _parseDate(List<String> lines) {
  final now = DateTime.now();
  final patterns = [
    (RegExp(r'(?<!\d)(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})(?!\d)'), true),
    (RegExp(r'(?<!\d)(\d{4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})(?!\d)'), false),
    (RegExp(r'ngay\s*(\d{1,2})\s*thang\s*(\d{1,2})\s*nam\s*(\d{4})'), true),
  ];
  for (final ln in lines) {
    final f = receiptKey(ln);
    for (final (pat, dmy) in patterns) {
      for (final m in pat.allMatches(f)) {
        final a = int.parse(m[1]!), b = int.parse(m[2]!), c = int.parse(m[3]!);
        var (d, mth, y) = dmy ? (a, b, c) : (c, b, a);
        if (y < 100) y += 2000;
        if (y < 2000 || y > now.year + 1 || mth < 1 || mth > 12 || d < 1 || d > 31) continue;
        final date = DateTime(y, mth, d);
        if (date.month != mth) continue; // 31/02
        final t = RegExp(r'(\d{1,2})[:h](\d{2})').firstMatch(f.substring(m.end, math.min(f.length, m.end + 12)));
        if (t != null && int.parse(t[1]!) < 24 && int.parse(t[2]!) < 60) {
          return DateTime(y, mth, d, int.parse(t[1]!), int.parse(t[2]!));
        }
        return date;
      }
    }
  }
  return null;
}

String? _merchant(List<String> lines) {
  String strip(String s) => s.replaceAll(RegExp(r'^[\s\-*:=#]+|[\s\-*:=#]+$'), '');
  final top = lines.take(8).toList();
  for (final ln in top) {
    final f = receiptKey(ln);
    if (knownMerchants.any(f.contains)) return strip(ln);
  }
  for (final ln in top.take(5)) {
    final f = receiptKey(ln);
    if (RegExp(r'[a-z]').allMatches(f).length >= 3 &&
        receiptAmounts(ln).isEmpty &&
        !_has(f, _notMerchant) &&
        !RegExp(r'\d{5,}').hasMatch(ln)) {
      return strip(ln);
    }
  }
  return null;
}

ParsedReceipt parseReceipt(String text) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) cleanOcrNumbers(l.trim())
  ];
  final merchant = _merchant(lines);
  double? cash, change, subtotal, discount;
  final candidates = <(int rank, double value)>[];
  var firstSummary = lines.length;
  for (var i = 0; i < lines.length; i++) {
    final f = receiptKey(lines[i]);
    var vals = receiptAmounts(lines[i]);
    if (vals.isEmpty && i + 1 < lines.length && !RegExp(r'[a-z]{3}').hasMatch(receiptKey(lines[i + 1]))) {
      vals = receiptAmounts(lines[i + 1]); // nhãn và số bị tách thành hai dòng
    }
    final exact = _has(f, _change) || _has(f, _cash) || _has(f, _subtotal);
    if (_has(f, _change, fuzzy: !exact)) {
      if (vals.isNotEmpty) change = vals.last;
      firstSummary = math.min(firstSummary, i);
      continue;
    }
    if (_has(f, _cash, fuzzy: !exact) && !_has(f, ['thanh toan bang', 'hinh thuc'])) {
      if (vals.isNotEmpty) cash = vals.last;
      firstSummary = math.min(firstSummary, i);
      continue;
    }
    if (_has(f, _subtotal, fuzzy: !exact)) {
      if (vals.isNotEmpty) subtotal = vals.last;
      firstSummary = math.min(firstSummary, i);
      continue;
    }
    if (_has(f, _notItem)) {
      if (_has(f, _discount) && vals.isNotEmpty) discount = (discount ?? 0) + vals.last;
      if (i > 2) firstSummary = math.min(firstSummary, i);
      continue;
    }
    for (final (key, rank) in _totalKeys) {
      if (RegExp('(?<![a-z])${RegExp.escape(key)}(?![a-z])').hasMatch(f) && vals.isNotEmpty) {
        candidates.add((rank, vals.last));
        firstSummary = math.min(firstSummary, i);
        break;
      }
    }
  }

  // Dòng hàng nằm giữa phần đầu (sau dòng tiêu đề cột) và phần tổng
  final items = <ReceiptLineItem>[];
  var start = 0;
  for (var i = 0; i < firstSummary; i++) {
    if (_has('${receiptKey(lines[i])} ', _header)) start = i + 1;
  }
  String? pending;
  for (final ln in lines.sublist(math.min(start, firstSummary), firstSummary)) {
    final f = receiptKey(ln);
    final vals = receiptAmounts(ln);
    var name = ln.replaceAll(RegExp(r'[\d.,]+\s*(đ|d|vnd)?\s*$', caseSensitive: false), '').trim();
    name = name.replaceAll(RegExp(r'\s+\d+\s*[xX*]?\s*[\d.,]*\s*$'), '').replaceAll(RegExp(r'^[\s.:\-*]+|[\s.:\-*]+$'), '');
    final hasText = RegExp(r'[a-z]').allMatches(f).length >= 2;
    if (_has(f, [..._notMerchant, ..._notItem]) || (merchant != null && ln.startsWith(merchant)) ||
        RegExp(r'^[\-=_*. ]+$').hasMatch(ln)) {
      pending = null;
      continue;
    }
    if (vals.isNotEmpty && hasText && name.replaceAll(RegExp(r'[^A-Za-zÀ-ỹ]'), '').length >= 2) {
      items.add(ReceiptLineItem(name, vals.last));
      pending = null;
    } else if (vals.isNotEmpty && pending != null) {
      items.add(ReceiptLineItem(pending, vals.last)); // dòng "2 x 12.000   24.000" dưới tên hàng
      pending = null;
    } else if (hasText && vals.isEmpty) {
      pending = ln.replaceAll(RegExp(r'^[\s.:\-*]+|[\s.:\-*]+$'), '');
    }
  }
  final itemsSum = items.fold<double>(0, (s, i) => s + i.amount);

  // Bỏ phiếu tổng tiền; mỗi giá trị kèm biến thể đã sửa lỗi OCR ("454.999" → "454.000")
  final sources = <(String, double, double)>[];
  if (candidates.isNotEmpty) {
    final best = candidates.map((c) => c.$1).reduce(math.min);
    for (final (rank, v) in candidates) {
      if (rank == best) sources.add(('dòng TỔNG', v, rank <= 1 ? 3 : 2));
    }
  }
  if (cash != null && change != null && cash > change) sources.add(('tiền khách đưa − tiền thừa', cash - change, 2));
  if (subtotal != null) {
    sources.add((discount != null ? 'tổng tiền hàng − giảm giá' : 'tổng tiền hàng', subtotal - (discount ?? 0), discount != null ? 2 : 1.5));
  }
  if (items.length >= 2) sources.add(('tổng các dòng hàng', itemsSum - (discount ?? 0), 1.5));

  List<(double, double)> variants(double v) {
    final out = [(v, 1.0)];
    if (v >= 10000 && v % 500 != 0) {
      final digits = v.round().toString();
      final tail = digits.substring(digits.length - 3).replaceAll(RegExp('[3689]'), '0');
      if (tail != digits.substring(digits.length - 3)) {
        out.add((double.parse(digits.substring(0, digits.length - 3) + tail), 0.9));
      }
      out.add(((v / 1000).round() * 1000.0, 0.8));
    }
    return out;
  }

  final votes = <double, double>{};
  final supporters = <double, Set<String>>{};
  for (final (name, v, w) in sources) {
    for (final (value, k) in variants(v)) {
      final key = value.roundToDouble();
      votes[key] = (votes[key] ?? 0) + w * k;
      (supporters[key] ??= {}).add(name);
    }
  }
  double? total;
  var confidence = 0.0;
  var checks = <String>[];
  if (votes.isNotEmpty) {
    total = votes.keys.reduce((a, b) {
      final c = votes[a]!.compareTo(votes[b]!);
      if (c != 0) return c > 0 ? a : b;
      return a % 500 == 0 ? a : b;
    });
    final weight = sources.fold<double>(0, (s, x) => s + x.$3);
    checks = supporters[total]!.toList()..sort();
    confidence = 0.35 + 0.5 * votes[total]! / weight + (checks.length >= 2 ? 0.1 : 0);
  } else {
    final all = [for (final l in lines) ...receiptAmounts(l)].where((v) => cash == null || v < cash).toList();
    if (all.isNotEmpty) {
      total = all.reduce(math.max);
      confidence = 0.25;
      checks = ['số lớn nhất trên hóa đơn'];
    }
  }
  final date = _parseDate(lines);
  if (date != null) confidence += 0.03;
  if (merchant != null) confidence += 0.02;
  return ParsedReceipt(
      merchant: merchant,
      total: total,
      date: date,
      items: items,
      confidence: math.min(1, (confidence * 100).roundToDouble() / 100),
      checks: checks);
}
