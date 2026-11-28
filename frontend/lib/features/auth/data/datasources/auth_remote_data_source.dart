import 'package:finance_app/features/auth/data/datasources/session_client.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);
  final SessionClient _client;

  Future<Map<String, dynamic>> _public(String path, Map<String, dynamic> body) =>
      _client.send('POST', '/auth$path', body: body, auth: false);

  Future<Map<String, dynamic>> login(String email, String password) =>
      _public('/login', {'email': email, 'password': password});

  Future<Map<String, dynamic>> register(String name, String email, String password) =>
      _public('/register', {'name': name, 'email': email, 'password': password});

  Future<void> verifyEmail(String token) async {
    await _public('/verify-email', {'token': token});
  }

  Future<Map<String, dynamic>> forgotPassword(String email) => _public('/forgot-password', {'email': email});

  Future<void> validateResetToken(String token) async {
    await _public('/reset-password/validate', {'token': token});
  }

  Future<void> resetPassword(String token, String newPassword, String confirmPassword) async {
    await _public('/reset-password', {
      'token': token,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    });
  }

  Future<Map<String, dynamic>> resendVerification(String email) => _public('/resend-verification', {'email': email});

  Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) =>
      _client.send('PUT', '/auth/change-password', body: {'oldPassword': oldPassword, 'newPassword': newPassword});

  Future<void> updateProfile(Map<String, dynamic> profile) => _client.send('PUT', '/auth/me', body: profile);

  Future<void> logout({String? refreshToken}) =>
      _client.send('POST', '/auth/logout', body: {'refreshToken': refreshToken});

  Future<void> deleteAccount(String password) => _client.send('DELETE', '/auth/me', body: {'password': password});
}
