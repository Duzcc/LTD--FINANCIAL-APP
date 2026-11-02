import 'package:finance_app/data/finance_provider.dart';

/// Yêu cầu nhận tiền bằng VietQR, đối soát tự động khi SePay báo tiền về.
class PaymentRequestInfo {
  const PaymentRequestInfo(
      {required this.id,
      required this.code,
      required this.walletId,
      required this.kind,
      required this.status,
      this.amount,
      this.personId,
      this.note = '',
      this.paidAmount,
      this.paidAt,
      this.entryId});
  final String id, code, walletId, kind, status, note;
  final double? amount, paidAmount;
  final String? personId, entryId;
  final DateTime? paidAt;
  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';

  factory PaymentRequestInfo.fromJson(Map<String, dynamic> j) =>
      PaymentRequestInfo(
          id: '${j['id']}',
          code: '${j['code']}',
          walletId: '${j['walletId']}',
          kind: '${j['kind'] ?? 'income'}',
          status: '${j['status'] ?? 'pending'}',
          amount: (j['amount'] as num?)?.toDouble(),
          personId: j['personId'] as String?,
          note: '${j['note'] ?? ''}',
          paidAmount: (j['paidAmount'] as num?)?.toDouble(),
          paidAt: DateTime.tryParse('${j['paidAt']}')?.toLocal(),
          entryId: j['entryId'] as String?);
}

/// Trạng thái kết nối webhook SePay của tài khoản.
class SepayStatus {
  const SepayStatus(
      {required this.connected, required this.webhookUrl, this.keyHint, this.apiKey});
  final bool connected;
  final String webhookUrl;
  final String? keyHint;

  /// Chỉ có ngay sau khi tạo khóa (máy chủ không lưu bản gốc).
  final String? apiKey;
  factory SepayStatus.fromJson(Map<String, dynamic> j) => SepayStatus(
      connected: j['connected'] == true || j['apiKey'] != null,
      webhookUrl: '${j['webhookUrl'] ?? ''}',
      keyHint: j['keyHint'] as String?,
      apiKey: j['apiKey'] as String?);
}

class BankRepository {
  BankRepository(this.p);
  final FinanceProvider p;

  Future<PaymentRequestInfo> create(
      {required String walletId,
      double? amount,
      String kind = 'income',
      String? personId,
      String note = ''}) async {
    final r = await p.bankRequest('POST', '/requests', body: {
      'walletId': walletId,
      if (amount != null) 'amount': amount.round(),
      'kind': kind,
      if (personId != null) 'personId': personId,
      'note': note.trim(),
    });
    return PaymentRequestInfo.fromJson(r);
  }

  Future<PaymentRequestInfo> get(String id) async =>
      PaymentRequestInfo.fromJson(await p.bankRequest('GET', '/requests/$id'));

  Future<PaymentRequestInfo> cancel(String id) async =>
      PaymentRequestInfo.fromJson(await p.bankRequest('DELETE', '/requests/$id'));

  Future<List<PaymentRequestInfo>> list() async {
    final r = await p.bankRequest('GET', '/requests');
    return [
      for (final j in (r['items'] as List? ?? const []))
        PaymentRequestInfo.fromJson((j as Map).cast<String, dynamic>())
    ];
  }

  Future<SepayStatus> sepay() async =>
      SepayStatus.fromJson(await p.bankRequest('GET', '/sepay'));

  Future<SepayStatus> createKey() async =>
      SepayStatus.fromJson(await p.bankRequest('POST', '/sepay/key'));

  Future<void> revokeKey() => p.bankRequest('DELETE', '/sepay/key');
}
