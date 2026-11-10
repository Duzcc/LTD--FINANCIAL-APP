import 'package:finance_app/core/utils/json_fields.dart';

class MoneyBudget {
  const MoneyBudget(
      {required this.id,
      required this.categoryId,
      required this.month,
      required this.amount,
      this.walletId,
      this.currency = 'VND',
      this.income = false});
  final String id, currency;
  final String? categoryId, walletId;
  final DateTime month;
  final double amount;
  final bool income;
  bool get isOverall => categoryId == null;
  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'month':
            '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
        'amount': amount,
        'walletId': walletId,
        'currency': currency,
        'income': income
      };
  factory MoneyBudget.fromJson(Map<String, dynamic> j) {
    final m = parseLocalDate(j['month'])!;
    return MoneyBudget(
        id: j['id'],
        categoryId: j['categoryId'],
        month: DateTime(m.year, m.month),
        amount: parseNumber(j['amount']),
        walletId: j['walletId'],
        currency: j['currency'] ?? 'VND',
        income: j['income'] == true);
  }
}
