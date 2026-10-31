import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lỗi trả về từ RESTful API (hoặc lỗi mạng khi [status] == 0).
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.body]);
  final int status;
  final String code, message;
  final Map<String, dynamic>? body;
  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  @override
  String toString() => message;
}

/// Ứng dụng (frontend) và backend chạy trên hai máy chủ khác nhau; địa chỉ
/// backend cấu hình bằng `--dart-define=API_URL=https://api.example.com`
/// hoặc trong màn hình đăng nhập (mục "Máy chủ").
class ApiClient {
  ApiClient({http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();
  final http.Client _client;
  final Duration timeout;

  static const _fromEnvironment = String.fromEnvironment('API_URL');
  static String get defaultBaseUrl {
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;
    // Máy ảo Android truy cập máy tính chạy backend qua 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static String normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return defaultBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/api')) u = u.substring(0, u.length - 4);
    return u;
  }

  Future<Map<String, dynamic>> send(String method, String baseUrl, String path,
      {Object? body, String? token}) async {
    final uri = Uri.parse('${normalize(baseUrl)}/api$path');
    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    http.Response response;
    try {
      response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT',
          'Máy chủ phản hồi quá lâu. Vui lòng kiểm tra kết nối và thử lại.');
    } catch (_) {
      throw const ApiException(0, 'NETWORK',
          'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ máy chủ.');
    }
    Map<String, dynamic> data = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        if (response.statusCode < 400) {
          throw const ApiException(
              0, 'BAD_RESPONSE', 'Địa chỉ máy chủ không đúng API của ứng dụng.');
        }
      }
    }
    if (response.statusCode >= 400) {
      final error = data['error'];
      throw ApiException(
          response.statusCode,
          error is Map ? '${error['code']}' : 'HTTP_${response.statusCode}',
          error is Map
              ? '${error['message']}'
              : 'Máy chủ trả về lỗi ${response.statusCode}.',
          data);
    }
    return data;
  }
}
