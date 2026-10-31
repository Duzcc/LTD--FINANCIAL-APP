import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/ocr/text_recognizer.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/ai/data/ai_models.dart';
import 'package:finance_app/features/ai/on_device/local_assistant.dart';
import 'package:finance_app/features/ai/on_device/quick_parser.dart';
import 'package:finance_app/features/ai/on_device/receipt_parser.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';

/// Cổng duy nhất của giao diện tới AI.
///
/// Chiến lược "server-first, device-fallback": khi đăng nhập và máy chủ có AI
/// service thì dùng mô hình máy chủ (chính xác hơn, cá nhân hóa); mất mạng hoặc
/// máy chủ không hỗ trợ thì tự dùng mô hình chạy trên thiết bị.
class AiRepository {
  AiRepository(this.p, {this.ocr = const TextRecognizer()});
  final FinanceProvider p;
  final TextRecognizer ocr;

  bool get remoteAvailable => p.signedIn;

  /// Phân tích câu nhập nhanh. Luôn trả kết quả (máy chủ hoặc thiết bị).
  Future<(ParsedEntry, bool remote)> parse(String text) async {
    final local = QuickEntryParser(p).parse(text);
    if (!remoteAvailable) return (local, false);
    try {
      final j = await p.aiRequest('POST', '/parse',
          body: {'text': text}, pushFirst: false);
      final kind = kindFromName(j['kind'] as String?);
      final walletId = j['walletId'] as String?;
      final remote = ParsedEntry(
          kind: kind,
          amount: (j['amount'] as num?)?.toDouble(),
          date: DateTime.tryParse('${j['date']}')?.toLocal() ?? local.date,
          note: '${j['note'] ?? local.note}',
          categoryId: p.category(j['categoryId'] as String?) == null
              ? local.categoryId
              : j['categoryId'] as String?,
          personId: j['personId'] as String?,
          newPersonName: j['newPersonName'] as String?,
          walletId: p.findWallet(walletId) == null ? local.walletId : walletId,
          confidence: (j['confidence'] as num?)?.toDouble() ?? 0);
      return remote.confidence >= local.confidence ? (remote, true) : (local, false);
    } on ApiException {
      return (local, false);
    }
  }

  /// Hỏi trợ lý. Máy chủ lỗi hoặc chỉ có trả lời theo luật -> trợ lý trên thiết bị.
  Future<AssistantReply> chat(List<Map<String, String>> history) async {
    final question = history.lastWhere((m) => m['role'] == 'user')['content']!;
    if (remoteAvailable) {
      try {
        final r = AssistantReply.fromJson(
            await p.aiRequest('POST', '/chat', body: {'messages': history}));
        if (r.reply.isNotEmpty && (r.source != 'rules' || r.actions.isNotEmpty)) {
          return r;
        }
      } on ApiException {
        // dùng trợ lý trên thiết bị
      }
    }
    return AssistantReply(LocalAssistant(p).answer(question), 'device');
  }

  /// Dự báo, bất thường và gợi ý ngân sách từ máy chủ; null nếu không khả dụng.
  Future<ServerInsights?> insights() async {
    if (!remoteAvailable) return null;
    try {
      final r = ServerInsights.fromJson(await p.aiRequest('GET', '/insights'));
      _cache = r;
      _cacheKey = _dataKey;
      insightsVersion.value++;
      return r;
    } on ApiException {
      return null;
    }
  }

  // Bộ nhớ tạm kết quả phân tích máy chủ để Tổng quan và màn Phân tích hiển thị cùng một con số.
  static ServerInsights? _cache;
  static String? _cacheKey;
  static Future<ServerInsights?>? _inflight;

  /// Tăng mỗi khi có kết quả phân tích mới từ máy chủ (để giao diện dựng lại).
  static final insightsVersion = ValueNotifier<int>(0);

  /// Khóa thay đổi khi dữ liệu (giao dịch, ngân sách), tài khoản hoặc ngày thay đổi.
  String get _dataKey {
    final now = DateTime.now();
    final sum = p.entries.fold<double>(0, (s, e) => s + e.amount);
    return '${p.session?.userId}|${p.entries.length}|$sum|${p.budgets.length}|${now.year}-${now.month}-${now.day}';
  }

  /// Kết quả máy chủ còn khớp dữ liệu hiện tại, hoặc null.
  ServerInsights? get cachedInsights => remoteAvailable && _cacheKey == _dataKey ? _cache : null;

  /// Lấy lại phân tích nền nếu kết quả cũ đã lỗi thời (không chặn giao diện, không gọi trùng).
  void refreshInsightsIfStale() {
    if (!remoteAvailable || cachedInsights != null || _inflight != null) return;
    // Chạy ở lượt sự kiện sau: hàm này được gọi trong lúc dựng giao diện.
    _inflight = Future(insights).whenComplete(() => _inflight = null);
  }

  /// Đọc hóa đơn từ ảnh:
  /// 1. nhận dạng chữ trên điện thoại (Apple Vision / ML Kit) — nhanh, không gửi ảnh đi;
  /// 2. có văn bản: phân tích ở máy chủ (gợi ý danh mục cá nhân hóa) hoặc trên thiết bị khi ngoại tuyến;
  /// 3. thiết bị không nhận dạng được: gửi ảnh cho AI service (Apple Vision/Tesseract/mô hình thị giác).
  Future<ReceiptResult> readReceipt(String imagePath) async {
    final recognized = await ocr.recognize(imagePath);
    final text = recognized?.text ?? '';
    if (text.trim().isNotEmpty) {
      final engine = recognized!.engine;
      if (remoteAvailable) {
        try {
          final r = await receiptFromText(text);
          if (r.total != null) return r.withSource('$engine + AI máy chủ', text: text);
        } on ApiException {
          // phân tích trên thiết bị
        }
      }
      return parseLocally(text, source: '$engine (trên thiết bị)');
    }
    if (!remoteAvailable) {
      throw const ApiException(0, 'OCR_UNAVAILABLE',
          'Thiết bị không nhận dạng được chữ trong ảnh. Hãy chụp rõ hơn hoặc đăng nhập để dùng AI máy chủ.');
    }
    final bytes = await File(imagePath).readAsBytes();
    final type = imagePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    return scanReceipt(bytes, type);
  }

  /// Phân tích văn bản hóa đơn trên thiết bị (ngoại tuyến), gợi ý danh mục bằng mô hình cục bộ.
  ReceiptResult parseLocally(String text, {String source = 'trên thiết bị'}) {
    final r = parseReceipt(text);
    final model = p.cached(() => CategoryModel.train(p.categories, p.entries));
    final hint = r.note.isEmpty ? (r.merchant ?? '') : r.note;
    return ReceiptResult(
        merchant: r.merchant,
        total: r.total,
        date: r.date,
        note: r.note,
        categoryId: hint.isEmpty ? null : model.suggest(hint, income: false),
        items: [for (final i in r.items) (i.name, i.amount)],
        source: source,
        confidence: r.confidence,
        checks: r.checks,
        rawText: text);
  }

  /// Đọc ảnh hóa đơn ở máy chủ. Ném [ApiException] (code AI_NOT_SUPPORTED khi
  /// máy chủ chưa có mô hình thị giác/Tesseract).
  Future<ReceiptResult> scanReceipt(Uint8List bytes, String mediaType) async =>
      ReceiptResult.fromJson(await p.aiRequest('POST', '/receipts/scan',
          body: {'image': base64Encode(bytes), 'mediaType': mediaType},
          pushFirst: false));

  Future<ReceiptResult> receiptFromText(String text) async =>
      ReceiptResult.fromJson(await p.aiRequest('POST', '/receipts/text',
          body: {'text': text}, pushFirst: false));

  /// Tìm kiếm ngữ nghĩa; trả về danh sách mã giao dịch theo độ liên quan.
  Future<(List<String> ids, Map<String, dynamic> filters)> search(String query) async {
    final r = await p.aiRequest('POST', '/search', body: {'query': query});
    return (
      [for (final h in (r['hits'] as List? ?? const [])) '${h['transactionId']}'],
      ((r['filters'] as Map?) ?? {}).cast<String, dynamic>()
    );
  }
}
