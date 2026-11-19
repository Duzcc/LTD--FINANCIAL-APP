import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/features/auth/domain/entities/account_session.dart';

class SessionClient {
  SessionClient(this.api,
      {required this.session,
      required this.serverUrl,
      required this.onRefreshed});

  final ApiClient api;
  final AccountSession? Function() session;
  final String Function() serverUrl;
  final void Function(AccountSession) onRefreshed;
  Future<void>? _refreshing;

  Future<Map<String, dynamic>> send(String method, String path,
      {Object? body, bool auth = true}) async {
    final sent = session();
    // hết phiên (401) thì xin phiên mới một lần rồi gửi lại,
    // nhiều request cùng lúc thì dùng chung một lần xin
    try {
      return await api.send(method, sent?.baseUrl ?? serverUrl(), path,
          body: body, token: auth ? sent?.token : null);
    } on ApiException catch (e) {
      if (!auth || !e.isUnauthorized || sent?.refreshToken == null) rethrow;
      if (identical(session(), sent)) {
        try {
          await (_refreshing ??=
              _refresh(sent!).whenComplete(() => _refreshing = null));
        } on ApiException {
          throw e;
        }
      }
      final next = session();
      if (next == null) rethrow;
      return api.send(method, next.baseUrl, path,
          body: body, token: next.token);
    }
  }

  Future<void> _refresh(AccountSession current) async {
    final r = await api.send('POST', current.baseUrl, '/auth/refresh',
        body: {'refreshToken': current.refreshToken});
    onRefreshed(current.withToken(r['token'] as String,
        refresh: r['refreshToken'] as String?));
  }
}
