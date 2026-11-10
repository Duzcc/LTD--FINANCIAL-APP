import 'package:finance_app/features/finance/domain/ledger_queries.dart';

abstract interface class FinanceStore implements LedgerQueries {
  bool get signedIn;
  String? get accountId;
  int get dataRevision;
  T cached<T>(T Function() build);
  Future<Map<String, dynamic>> aiRequest(String method, String path, {Object? body, bool pushFirst = true});
  Future<Map<String, dynamic>> bankRequest(String method, String path, {Object? body});
}
