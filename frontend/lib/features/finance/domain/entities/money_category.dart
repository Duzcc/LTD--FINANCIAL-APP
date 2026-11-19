import 'package:finance_app/core/utils/json_fields.dart';

class MoneyCategory {
  const MoneyCategory(this.id, this.name, this.income, this.symbol);
  final String id, name;
  final bool income;
  final int symbol;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'income': income, 'symbol': symbol};
  factory MoneyCategory.fromJson(Map<String, dynamic> j) =>
      MoneyCategory(j['id'], j['name'], j['income'] == true, parseNumber(j['symbol']).toInt());
}
