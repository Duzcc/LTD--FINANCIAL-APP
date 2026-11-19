class PaymentRequestInfo {
  const PaymentRequestInfo(
      {required this.id,
      required this.code,
      required this.status,
      this.amount,
      this.personId,
      this.note = '',
      this.paidAmount});
  final String id, code, status, note;
  final double? amount, paidAmount;
  final String? personId;
  bool get isPaid => status == 'paid';
  bool get isPending => status == 'pending';

  factory PaymentRequestInfo.fromJson(Map<String, dynamic> j) => PaymentRequestInfo(
      id: '${j['id']}',
      code: '${j['code']}',
      status: '${j['status'] ?? 'pending'}',
      amount: (j['amount'] as num?)?.toDouble(),
      personId: j['personId'] as String?,
      note: '${j['note'] ?? ''}',
      paidAmount: (j['paidAmount'] as num?)?.toDouble());
}
