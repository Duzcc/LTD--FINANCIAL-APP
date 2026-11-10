import 'package:finance_app/features/finance/domain/entities/entities.dart';

class AccountSnapshot {
  AccountSnapshot(this.json);
  final Map<String, dynamic> json;

  List<T> _list<T>(String key, T Function(Map<String, dynamic>) parse) =>
      ((json[key] as List?) ?? const [])
          .map((v) => parse(Map<String, dynamic>.from(v as Map)))
          .toList();

  List<MoneyWallet> get wallets => _list('wallets', MoneyWallet.fromJson);
  List<MoneyCategory> get categories => _list('categories', MoneyCategory.fromJson);
  List<MoneyPerson> get people => _list('people', MoneyPerson.fromJson);
  List<MoneyEntry> get entries => _list('entries', MoneyEntry.fromJson);
  List<MoneyBudget> get budgets => _list('budgets', MoneyBudget.fromJson);
  List<RecurringRule> get recurring => _list('recurring', RecurringRule.fromJson);
  Map<String, dynamic>? get user =>
      json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : null;

  bool get hasData {
    int count(String key) => (json[key] as List?)?.length ?? 0;
    final wallets = (json['wallets'] as List?) ?? const [];
    return count('entries') > 0 ||
        count('budgets') > 0 ||
        count('people') > 1 ||
        wallets.length > 1 ||
        wallets.any((w) => w is Map && (w['opening'] ?? 0) != 0);
  }
}
