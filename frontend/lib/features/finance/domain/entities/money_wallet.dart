import 'package:finance_app/core/utils/json_fields.dart';

class MoneyWallet {
  const MoneyWallet(
      {required this.id,
      required this.name,
      this.opening = 0,
      this.currency = 'VND',
      this.savings = false,
      this.excluded = false,
      this.notify = false,
      this.symbol,
      this.target = 0,
      this.startDate,
      this.deadline,
      this.bankBin,
      this.bankAccount,
      this.bankHolder});
  final String id, name, currency;
  final double opening, target;
  final bool savings, excluded, notify;
  final int? symbol;
  final DateTime? startDate, deadline;

  final String? bankBin, bankAccount, bankHolder;
  bool get hasBank => bankBin != null && bankAccount != null;
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'opening': opening,
        'currency': currency,
        'savings': savings,
        'excluded': excluded,
        'notify': notify,
        'symbol': symbol,
        'target': target,
        'startDate': isoUtc(startDate),
        'deadline': isoUtc(deadline),
        'bankBin': bankBin,
        'bankAccount': bankAccount,
        'bankHolder': bankHolder
      };
  factory MoneyWallet.fromJson(Map<String, dynamic> j) => MoneyWallet(
      id: j['id'],
      name: j['name'],
      opening: parseNumber(j['opening']),
      currency: j['currency'] ?? 'VND',
      savings: j['savings'] == true,
      excluded: j['excluded'] == true,
      notify: j['notify'] == true,
      symbol: (j['symbol'] as num?)?.toInt(),
      target: parseNumber(j['target']),
      startDate: parseLocalDate(j['startDate']),
      deadline: parseLocalDate(j['deadline']),
      bankBin: j['bankBin'] as String?,
      bankAccount: j['bankAccount'] as String?,
      bankHolder: j['bankHolder'] as String?);
}
