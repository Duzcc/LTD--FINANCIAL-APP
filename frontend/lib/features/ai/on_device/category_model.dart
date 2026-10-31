import 'dart:math' as math;
import 'package:finance_app/data/models/finance_models.dart';

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Chuẩn hóa tiếng Việt: chữ thường, bỏ dấu, chỉ giữ chữ và số.
String foldVietnamese(String text) {
  final lower = text.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Như [foldVietnamese] nhưng giữ dấu chấm/phẩy giữa các chữ số và dấu "/"
/// để đọc số tiền ("1.250.000", "1,5tr") và ngày ("5/10").
String foldKeepNumbers(String text) {
  final lower = text.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    final i = _from.indexOf(ch);
    b.write(i >= 0 ? _to[i] : ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9.,/]+'), ' ')
      .replaceAll(RegExp(r'(?<!\d)[.,]|[.,](?!\d)'), ' ')
      .replaceAll(RegExp(r' +'), ' ')
      .trim();
}

List<String> tokenize(String text) {
  final words = foldVietnamese(text).split(' ').where((w) => w.isNotEmpty).toList();
  // Từ đơn và cặp từ liền nhau ("ca phe", "do xang") để bắt cụm từ tiếng Việt.
  return [
    ...words,
    for (var i = 0; i + 1 < words.length; i++) '${words[i]} ${words[i + 1]}',
  ];
}

/// Từ khóa khởi tạo cho các danh mục mặc định (giúp gợi ý ngay cả khi chưa có lịch sử).
const seedKeywords = <String, List<String>>{
  'food': ['an', 'com', 'pho', 'bun', 'banh mi', 'ca phe', 'cafe', 'tra sua', 'nuoc', 'an sang', 'an trua', 'an toi', 'nha hang', 'lau', 'nuong', 'do an', 'grabfood', 'shopeefood', 'cho', 'sieu thi', 'trai cay', 'banh', 'kem', 'bia'],
  'life': ['dien', 'nuoc', 'internet', 'wifi', 'mang', 'gas', 'dien thoai', 'cuoc', 'nap the', 'giat', 've sinh', 'do dung'],
  'house': ['nha', 'thue nha', 'tien nha', 'phong tro', 'sua nha', 'noi that', 'tien phong'],
  'self': ['quan ao', 'giay', 'my pham', 'cat toc', 'spa', 'sach', 'hoc', 'khoa hoc', 'game', 'phim', 'du lich', 'mua sam', 'shopee', 'lazada', 'tiki', 'qua'],
  'transport': ['xang', 'do xang', 'grab', 'be', 'taxi', 'xe', 'gui xe', 've xe', 'xe buyt', 'bus', 'tau', 'may bay', 'sua xe', 'rua xe', 'gojek', 'xanh sm'],
  'health': ['thuoc', 'kham', 'benh vien', 'nha thuoc', 'bao hiem', 'rang', 'vitamin', 'gym', 'tap'],
  'child': ['con', 'hoc phi', 'sua', 'ta', 'do choi', 'tre'],
  'salary': ['luong', 'luong thang', 'tien luong'],
  'bonus': ['thuong', 'tet', 'li xi', 'hoa hong'],
  'business': ['ban hang', 'kinh doanh', 'doanh thu', 'loi nhuan', 'khach'],
  'other_income': ['lam them', 'freelance', 'ban do', 'hoan tien', 'cashback', 'lai'],
};

/// Mô hình Naive Bayes đa thức chạy hoàn toàn trên thiết bị, học từ ghi chú
/// của chính người dùng: ghi chú → danh mục. Không gửi dữ liệu ra ngoài.
class CategoryModel {
  CategoryModel._(this._counts, this._totals, this._docs, this._vocab, this._income);
  final Map<String, Map<String, double>> _counts;
  final Map<String, double> _totals, _docs;
  final Set<String> _vocab;
  final Map<String, bool> _income;

  int get trainingSize => _docs.values.fold(0.0, (a, b) => a + b).round();

  factory CategoryModel.train(List<MoneyCategory> categories, List<MoneyEntry> entries) {
    final counts = <String, Map<String, double>>{};
    final totals = <String, double>{}, docs = <String, double>{};
    final vocab = <String>{};
    final income = {for (final c in categories) c.id: c.income};
    void learn(String category, List<String> tokens, double weight) {
      final m = counts.putIfAbsent(category, () => {});
      for (final t in tokens) {
        m[t] = (m[t] ?? 0) + weight;
        totals[category] = (totals[category] ?? 0) + weight;
        vocab.add(t);
      }
    }

    for (final c in categories) {
      docs[c.id] = 1;
      learn(c.id, tokenize(c.name), 2);
      for (final k in seedKeywords[c.id] ?? const <String>[]) {
        learn(c.id, tokenize(k), 1);
      }
    }
    for (final e in entries) {
      final c = e.categoryId;
      if (c == null || !income.containsKey(c) || e.note.trim().isEmpty) continue;
      docs[c] = (docs[c] ?? 0) + 1;
      // Lịch sử của người dùng có trọng số cao hơn từ khóa mặc định.
      learn(c, tokenize(e.note), 3);
    }
    return CategoryModel._(counts, totals, docs, vocab, income);
  }

  /// Xác suất từng danh mục cho [text], sắp xếp giảm dần.
  List<(String categoryId, double probability)> predict(String text, {required bool income}) {
    final tokens = tokenize(text).where(_vocab.contains).toList();
    if (tokens.isEmpty) return const [];
    final candidates = _income.entries.where((e) => e.value == income).map((e) => e.key).toList();
    if (candidates.isEmpty) return const [];
    final allDocs = candidates.fold(0.0, (s, c) => s + (_docs[c] ?? 1));
    final v = _vocab.length.toDouble();
    final logs = <String, double>{};
    for (final c in candidates) {
      var score = math.log((_docs[c] ?? 1) / allDocs);
      final counts = _counts[c] ?? const {};
      final total = _totals[c] ?? 0;
      for (final t in tokens) {
        score += math.log(((counts[t] ?? 0) + 0.1) / (total + 0.1 * v));
      }
      logs[c] = score;
    }
    final best = logs.values.reduce(math.max);
    final exp = {for (final e in logs.entries) e.key: math.exp(e.value - best)};
    final sum = exp.values.fold(0.0, (a, b) => a + b);
    final result = [for (final e in exp.entries) (e.key, e.value / sum)]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return result;
  }

  /// Danh mục đề xuất nếu đủ tự tin.
  String? suggest(String text, {required bool income, double minProbability = .45}) {
    final r = predict(text, income: income);
    if (r.isEmpty || r.first.$2 < minProbability) return null;
    return r.first.$1;
  }
}
