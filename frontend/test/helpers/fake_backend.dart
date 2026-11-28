import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';

class FakeBackend {
  final requests = <http.Request>[];
  Map<String, dynamic> snapshot = jsonDecode(jsonEncode({
    'user': {'id': 'u1', 'name': 'An', 'email': 'an@test.vn', 'currency': 'VND'},
    'wallets': [
      {'id': 'cash', 'name': 'Tiền mặt', 'opening': 0, 'currency': 'VND'}
    ],
    'categories': [
      {'id': 'food', 'name': 'Ăn uống', 'income': false, 'symbol': 0},
      {'id': 'salary', 'name': 'Lương', 'income': true, 'symbol': 7},
    ],
    'people': [
      {'id': 'self', 'name': 'Bản thân', 'group': 'Cá nhân'}
    ],
    'entries': <dynamic>[],
    'budgets': <dynamic>[],
  }));
  List<Map<String, dynamic>> batches = [];
  Map<String, dynamic>? bankRequest;
  String? verifiedEmailToken;
  Map<String, dynamic>? resetRequest;
  Map<String, dynamic> forgotPasswordResult = {
    'registered': true,
    'verified': true,
    'mailEnabled': true,
    'message': 'Đã gửi liên kết đặt lại mật khẩu. Hãy kiểm tra hộp thư.',
  };

  final ai = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{};
  final aiCalls = <String>[];

  String token = 'tok';
  String refreshToken = 'r0';
  int refreshCalls = 0;

  MockClient get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Map<String, dynamic> body() => request.body.isEmpty ? {} : jsonDecode(request.body);
        http.Response json(Object data, [int status = 200]) =>
            http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'});
        if (path == '/api/auth/login') {
          if (body()['password'] != '123456') {
            return json({
              'error': {'code': 'UNAUTHORIZED', 'message': 'Email hoặc mật khẩu không đúng.'}
            }, 401);
          }
          return json({
            'token': token,
            'refreshToken': refreshToken,
            'user': snapshot['user'],
          });
        }
        if (path == '/api/auth/register') {
          return json({
            'message': 'Hãy xác minh email.',
            'devLink': 'http://10.0.2.2:3000/api/auth/open-app/verify-email?token=testing'
          });
        }
        if (path == '/api/auth/verify-email') {
          verifiedEmailToken = body()['token'] as String?;
          return json({'message': 'Email đã được xác minh.'});
        }
        if (path == '/api/auth/forgot-password') {
          return json(forgotPasswordResult);
        }
        if (path == '/api/auth/reset-password/validate') {
          return json({'valid': true});
        }
        if (path == '/api/auth/reset-password') {
          resetRequest = body();
          return json({'message': 'Mật khẩu đã được cập nhật.'});
        }
        if (path == '/api/auth/resend-verification') {
          return json({'message': 'Nếu email đã đăng ký, hãy kiểm tra hộp thư.'});
        }
        if (path == '/api/auth/refresh') {
          refreshCalls++;
          if (body()['refreshToken'] != refreshToken) {
            return json({
              'error': {'code': 'UNAUTHORIZED', 'message': 'Hết phiên'}
            }, 401);
          }
          refreshToken = 'r$refreshCalls';
          return json({'token': token, 'refreshToken': refreshToken});
        }
        if (request.headers['Authorization'] != 'Bearer $token') {
          return json({
            'error': {'code': 'UNAUTHORIZED', 'message': 'Hết phiên'}
          }, 401);
        }
        if (path == '/api/sync' && request.method == 'GET') {
          return json(snapshot);
        }
        if (path == '/api/sync/batch') {
          final b = body();
          batches.add(b);
          for (final op in b['ops'] as List) {
            final list = snapshot[op['entity']] as List;
            list.removeWhere((x) => x['id'] == op['id']);
            if (op['action'] == 'upsert') {
              list.add(<String, dynamic>{...(op['data'] as Map).cast<String, dynamic>(), 'id': op['id']});
            }
          }
          return json({'applied': (b['ops'] as List).length});
        }
        if (path.startsWith('/api/ai/')) {
          aiCalls.add(path);
          final handler = ai[path];
          if (handler == null) {
            return json({
              'error': {'code': 'AI_UNAVAILABLE', 'message': 'AI tắt'}
            }, 503);
          }
          return json(handler(body()));
        }
        if (path == '/api/bank/requests' && request.method == 'POST') {
          final b = body();
          bankRequest = {
            'id': 'pr1',
            'code': 'LTDAB23CD',
            'status': 'pending',
            ...b,
          };
          return json(bankRequest!, 201);
        }
        if (path == '/api/bank/requests/pr1') {
          return json(bankRequest!);
        }
        if (path == '/api/auth/me') return json({'user': snapshot['user']});
        if (path == '/api/auth/logout') return http.Response('', 204);
        return json({
          'error': {'code': 'NOT_FOUND', 'message': 'x'}
        }, 404);
      });
}

Future<bool> signIn(FinanceProvider p, {String email = 'an@test.vn', String password = '123456'}) =>
    p.signIn(email: email, password: password);
