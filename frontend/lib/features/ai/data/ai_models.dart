import 'package:finance_app/data/models/finance_models.dart';

double? _num(Object? v) => v is num ? v.toDouble() : null;
DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// Hành động trợ lý đề xuất; chỉ thực hiện khi người dùng xác nhận.
class AssistantAction {
  const AssistantAction(this.type, this.data);
  final String type; // create_transaction | set_budget
  final Map<String, dynamic> data;
  factory AssistantAction.fromJson(Map<String, dynamic> j) => AssistantAction(
      '${j['type']}', (j['data'] as Map? ?? {}).cast<String, dynamic>());
}

class AssistantReply {
  const AssistantReply(this.reply, this.source,
      {this.actions = const [], this.toolsUsed = const []});
  final String reply;

  /// ai-service | llm | rules | device
  final String source;
  final List<AssistantAction> actions;
  final List<String> toolsUsed;
  factory AssistantReply.fromJson(Map<String, dynamic> j) => AssistantReply(
      '${j['reply'] ?? ''}', '${j['source'] ?? 'server'}',
      actions: [
        for (final a in (j['actions'] as List? ?? const []))
          if (a is Map) AssistantAction.fromJson(a.cast<String, dynamic>())
      ],
      toolsUsed: [for (final t in (j['toolsUsed'] as List? ?? const [])) '$t']);
}

class ForecastResult {
  const ForecastResult(
      {required this.spent,
      required this.projected,
      required this.lower,
      required this.upper,
      required this.daysLeft,
      required this.method,
      this.nextMonth,
      this.byCategory = const {}});
  final double spent, projected, lower, upper;
  final int daysLeft;
  final String method;
  final double? nextMonth;
  final Map<String, double> byCategory; // dự kiến theo danh mục
  factory ForecastResult.fromJson(Map<String, dynamic> j) => ForecastResult(
      spent: _num(j['spent']) ?? 0,
      projected: _num(j['projected']) ?? 0,
      lower: _num(j['lower']) ?? 0,
      upper: _num(j['upper']) ?? 0,
      daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
      method: '${j['method'] ?? ''}',
      nextMonth: _num(j['nextMonth']),
      byCategory: {
        for (final e in ((j['byCategory'] as Map?) ?? {}).entries)
          '${e.key}': _num((e.value as Map?)?['projected']) ?? 0
      });
}

class AnomalyItem {
  const AnomalyItem(this.transactionId, this.score, this.kind, this.reasons);
  final String transactionId, kind;
  final double score;
  final List<String> reasons;
}

class CategorySpike {
  const CategorySpike(this.categoryId, this.recent, this.baseline, this.ratio);
  final String categoryId;
  final double recent, baseline, ratio;
}

class BudgetSuggestion {
  const BudgetSuggestion(this.categoryId, this.amount, this.group, this.note);
  final String categoryId, group, note;
  final double amount;
}

/// Kết quả tổng hợp từ /api/ai/insights (phần nào lỗi thì null).
class ServerInsights {
  const ServerInsights(
      {this.forecast,
      this.anomalies = const [],
      this.spikes = const [],
      this.budgets = const [],
      this.plan});
  final ForecastResult? forecast;
  final List<AnomalyItem> anomalies;
  final List<CategorySpike> spikes;
  final List<BudgetSuggestion> budgets;
  final Map<String, dynamic>? plan;

  factory ServerInsights.fromJson(Map<String, dynamic> j) {
    final a = j['anomalies'] as Map?;
    final b = j['budgets'] as Map?;
    return ServerInsights(
        forecast: j['forecast'] is Map
            ? ForecastResult.fromJson((j['forecast'] as Map).cast())
            : null,
        anomalies: [
          for (final x in (a?['anomalies'] as List? ?? const []))
            AnomalyItem('${x['transactionId']}', _num(x['score']) ?? 0,
                '${x['kind']}', [for (final r in x['reasons'] as List) '$r'])
        ],
        spikes: [
          for (final x in (a?['spikes'] as List? ?? const []))
            CategorySpike('${x['categoryId']}', _num(x['recent']) ?? 0,
                _num(x['baseline']) ?? 0, _num(x['ratio']) ?? 0)
        ],
        budgets: [
          for (final x in (b?['suggestions'] as List? ?? const []))
            BudgetSuggestion('${x['categoryId']}', _num(x['amount']) ?? 0,
                '${x['group']}', '${x['note'] ?? ''}')
        ],
        plan: (b?['plan'] as Map?)?.cast<String, dynamic>());
  }
}

class ReceiptResult {
  const ReceiptResult(
      {this.merchant,
      this.total,
      this.date,
      this.note = '',
      this.categoryId,
      this.items = const [],
      this.source = '',
      this.confidence = 0,
      this.checks = const [],
      this.rawText = ''});
  final String? merchant, categoryId;
  final double? total;
  final DateTime? date;
  final String note, source, rawText;
  final List<(String, double)> items;

  /// 0–1: tổng tiền được xác nhận bởi bao nhiêu nguồn độc lập trên hóa đơn.
  final double confidence;
  final List<String> checks;

  factory ReceiptResult.fromJson(Map<String, dynamic> j) => ReceiptResult(
      merchant: j['merchant'] as String?,
      total: _num(j['total']),
      date: _date(j['date']),
      note: '${j['note'] ?? ''}',
      categoryId: j['categoryId'] as String?,
      source: '${j['source'] ?? ''}',
      confidence: _num(j['confidence']) ?? 0,
      checks: [for (final c in (j['checks'] as List? ?? const [])) '$c'],
      rawText: '${j['rawText'] ?? ''}',
      items: [
        for (final i in (j['items'] as List? ?? const []))
          ('${i['name']}', _num(i['amount']) ?? 0)
      ]);

  ReceiptResult withSource(String value, {String? text}) => ReceiptResult(
      merchant: merchant,
      total: total,
      date: date,
      note: note,
      categoryId: categoryId,
      items: items,
      source: value,
      confidence: confidence,
      checks: checks,
      rawText: text ?? rawText);
}

EntryKind kindFromName(String? name) =>
    EntryKind.values.where((k) => k.name == name).firstOrNull ??
    EntryKind.expense;
