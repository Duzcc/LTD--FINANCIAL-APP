import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:finance_app/data/finance_provider.dart';

/// Backend giả lập tối giản để kiểm tra luồng đăng nhập và đồng bộ của app.
class FakeBackend {
  final requests = <http.Request>[];
  // Đi qua JSON để mọi danh sách là List<dynamic> giống dữ liệu thật từ API.
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
  static const otpCode = '123456';

  /// Yêu cầu nhận tiền VietQR gần nhất (test đổi 'status' để giả lập SePay báo tiền về).
  Map<String, dynamic>? bankRequest;

  /// Phản hồi giả cho các API AI (đường dẫn -> hàm tạo JSON). Thiếu = 503.
  final ai = <String, Map<String, dynamic> Function(Map<String, dynamic>)>{};
  final aiCalls = <String>[];

  MockClient get client => MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Map<String, dynamic> body() =>
            request.body.isEmpty ? {} : jsonDecode(request.body);
        http.Response json(Object data, [int status = 200]) => http.Response(
            jsonEncode(data), status,
            headers: {'content-type': 'application/json; charset=utf-8'});
        if (path == '/api/auth/login') {
          if (body()['password'] != '123456') {
            return json({
              'error': {
                'code': 'UNAUTHORIZED',
                'message': 'Email hoặc mật khẩu không đúng.'
              }
            }, 401);
          }
          return json({
            'otpRequired': true,
            'otpToken': 'otp1',
            'email': body()['email'],
            'devCode': otpCode,
            'expiresIn': 300,
            'resendAfter': 60,
          });
        }
        if (path == '/api/auth/verify-otp') {
          if (body()['otpToken'] != 'otp1' || body()['code'] != otpCode) {
            return json({
              'error': {
                'code': 'INVALID_CODE',
                'message': 'Mã OTP không đúng. Bạn còn 4 lần thử.'
              }
            }, 400);
          }
          return json({'token': 'tok', 'user': snapshot['user']});
        }
        if (request.headers['Authorization'] != 'Bearer tok') {
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
              list.add(<String, dynamic>{
                ...(op['data'] as Map).cast<String, dynamic>(),
                'id': op['id']
              });
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


/// Đăng nhập hai bước như ứng dụng thật: mật khẩu rồi mã OTP.
Future<bool> signInWithOtp(FinanceProvider p,
    {String email = 'an@test.vn', String password = '123456'}) async {
  final challenge = await p.signIn(email: email, password: password);
  return p.verifyOtp(challenge, challenge.devCode!);
}
