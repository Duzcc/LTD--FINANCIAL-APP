import 'package:finance_app/features/banking/domain/entities/payment_request.dart';
import 'package:finance_app/features/banking/domain/entities/sepay_status.dart';
import 'package:finance_app/features/finance/domain/finance_store.dart';

export 'package:finance_app/features/banking/domain/entities/payment_request.dart';
export 'package:finance_app/features/banking/domain/entities/sepay_status.dart';

class BankRepository {
  BankRepository(this.p);
  final FinanceStore p;

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
