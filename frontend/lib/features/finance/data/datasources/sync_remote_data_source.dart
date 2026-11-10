import 'package:finance_app/features/auth/data/datasources/session_client.dart';

class SyncRemoteDataSource {
  SyncRemoteDataSource(this._client);
  final SessionClient _client;

  Future<Map<String, dynamic>> fetchSnapshot() => _client.send('GET', '/sync');

  Future<void> pushBatch(List<Map<String, dynamic>> ops) =>
      _client.send('POST', '/sync/batch', body: {'ops': ops});
}
