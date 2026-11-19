import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/features/ai/data/datasources/text_recognizer.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/domain/finance_store.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/domain/services/local_assistant.dart';
import 'package:finance_app/features/ai/domain/services/quick_parser.dart';
import 'package:finance_app/features/ai/domain/services/receipt_parser.dart';
import 'package:finance_app/features/ai/domain/services/category_model.dart';
import 'package:finance_app/features/ai/domain/services/reminder_parser.dart';

class AiRepository {
  AiRepository(this.p, {this.ocr = const TextRecognizer()});
  final FinanceStore p;
  final TextRecognizer ocr;

  bool get remoteAvailable => p.signedIn;

  Future<(ParsedEntry, bool remote)> parse(String text) async {
    final local = QuickEntryParser(p).parse(text);
    if (!remoteAvailable) return (local, false);
    final j = await p
        .aiRequest('POST', '/parse', body: {'text': text}, pushFirst: false)
        .orNullOnApiError();
    if (j == null) return (local, false);
    final walletId = j['walletId'] as String?;
    final remote = ParsedEntry(
        kind: kindFromName(j['kind'] as String?),
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
  }

  Future<AssistantReply> chat(List<Map<String, String>> history) async {
    final question = history.lastWhere((m) => m['role'] == 'user')['content']!;
    final reminder = ReminderParser().parse(question);
    if (reminder != null) {
      return AssistantReply('Mình đã chuẩn bị nhắc nhở, bấm Xác nhận để bật thông báo nhé.', 'device', actions: [
        AssistantAction('create_reminder',
            {'title': reminder.title, 'at': reminder.at.toIso8601String(), 'repeat': reminder.repeat.name})
      ]);
    }
    if (remoteAvailable) {
      final r = await p
          .aiRequest('POST', '/chat', body: {'messages': history})
          .then(AssistantReply.fromJson)
          .orNullOnApiError();
      if (r != null && r.reply.isNotEmpty && (r.source != 'rules' || r.actions.isNotEmpty)) {
        return r;
      }
    }
    return LocalAssistant(p).reply(question);
  }

  Future<ServerInsights?> insights() async {
    if (!remoteAvailable) return null;
    final key = _dataKey;
    final j = await p.aiRequest('GET', '/insights').orNullOnApiError();
    if (j == null) {
      _retryAt = DateTime.now().add(_retryDelay);
      _retryKey = _sessionKey;
      return null;
    }
    final r = ServerInsights.fromJson(j);
    _cache = r;
    _cacheKey = key;
    _retryAt = null;
    insightsVersion.value++;
    return r;
  }

  static ServerInsights? _cache;
  static String? _cacheKey;
  static Future<ServerInsights?>? _inflight;
  static DateTime? _retryAt;
  static String? _retryKey;
  static const _retryDelay = Duration(minutes: 1);

  static final insightsVersion = ValueNotifier<int>(0);

  String get _sessionKey => '${identityHashCode(p)}|${p.accountId}';

  String get _dataKey {
    final now = DateTime.now();
    return '$_sessionKey|${p.dataRevision}|${now.year}-${now.month}-${now.day}';
  }

  ServerInsights? get cachedInsights => remoteAvailable && _cacheKey == _dataKey ? _cache : null;

  // chỉ phân tích khi đã sao lưu xong, sửa liên tục thì chỉ gọi một lần
  void refreshInsightsIfStale() {
    if (!remoteAvailable || cachedInsights != null || _inflight != null) return;
    if (p.syncing || p.pendingChanges > 0) return;
    final retryAt = _retryAt;
    if (_retryKey == _sessionKey && retryAt != null && DateTime.now().isBefore(retryAt)) return;
    _inflight = insights().whenComplete(() => _inflight = null);
  }

  Future<ReceiptResult> readReceipt(String imagePath) async {
    final recognized = await ocr.recognize(imagePath);
    final text = recognized?.text ?? '';
    if (text.trim().isNotEmpty) {
      final engine = recognized!.engine;
      if (remoteAvailable) {
        final r = await receiptFromText(text).orNullOnApiError();
        if (r?.total != null) return categorize(r!.withSource('$engine + Trợ lý AI', text: text));
      }
      return parseLocally(text, source: '$engine (trên thiết bị)');
    }
    if (!remoteAvailable) {
      throw const ApiException(0, 'OCR_UNAVAILABLE',
          'Không nhận dạng được chữ trong ảnh. Hãy chụp rõ hơn hoặc đăng nhập để Trợ lý AI đọc giúp.');
    }
    final bytes = await File(imagePath).readAsBytes();
    final type = imagePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    return categorize(await scanReceipt(bytes, type));
  }

  CategoryModel get _model => p.cached(() => CategoryModel.train(p.categories, p.entries));

  // khoản thu chỉ nhận danh mục thu, khoản chi chỉ nhận danh mục chi
  ReceiptResult categorize(ReceiptResult r, [EntryKind? kind]) {
    final k = kind ?? r.kind;
    final income = k == EntryKind.income;
    String? sameKind(String? id) => p.category(id)?.income == income ? id : null;
    final hint = r.note.isEmpty ? (r.merchant ?? '') : r.note;
    final categoryId = sameKind(r.categoryId) ?? (hint.isEmpty ? null : _model.suggest(hint, income: income));
    return r.categorized(k, categoryId, [
      for (final i in r.items)
        i.withCategory(sameKind(i.categoryId) ?? _model.suggest(i.name, income: income) ?? categoryId)
    ]);
  }

  ReceiptResult parseLocally(String text, {String source = 'trên thiết bị'}) {
    final r = parseReceipt(text);
    return categorize(ReceiptResult(
        merchant: r.merchant,
        total: r.total,
        date: r.date,
        note: r.note,
        items: [
          for (final i in r.items) ReceiptItem(i.name, i.amount, quantity: i.quantity, unitPrice: i.unitPrice)
        ],
        source: source,
        confidence: r.confidence,
        checks: r.checks,
        rawText: text,
        kind: r.kind));
  }

  Future<ReceiptResult> scanReceipt(Uint8List bytes, String mediaType) async =>
      ReceiptResult.fromJson(await p.aiRequest('POST', '/receipts/scan',
          body: {'image': base64Encode(bytes), 'mediaType': mediaType},
          pushFirst: false));

  Future<ReceiptResult> receiptFromText(String text) async =>
      ReceiptResult.fromJson(await p.aiRequest('POST', '/receipts/text',
          body: {'text': text}, pushFirst: false));

  Future<(List<String> ids, Map<String, dynamic> filters)> search(String query) async {
    final r = await p.aiRequest('POST', '/search', body: {'query': query});
    return (
      [for (final h in (r['hits'] as List? ?? const [])) '${h['transactionId']}'],
      ((r['filters'] as Map?) ?? {}).cast<String, dynamic>()
    );
  }
}
