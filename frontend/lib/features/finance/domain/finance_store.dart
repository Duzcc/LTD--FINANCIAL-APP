import 'package:finance_app/features/finance/domain/ledger_queries.dart';

abstract interface class FinanceStore implements LedgerQueries {
  bool get signedIn;
  String? get accountId;
  int get dataRevision;
  bool get syncing;
  int get pendingChanges;
  T cached<T>(T Function() build);
  Future<Map<String, dynamic>> aiRequest(String method, String path,
      {Object? body, bool pushFirst = true, Duration? timeout});
  Future<Map<String, dynamic>> bankRequest(String method, String path, {Object? body});
}
