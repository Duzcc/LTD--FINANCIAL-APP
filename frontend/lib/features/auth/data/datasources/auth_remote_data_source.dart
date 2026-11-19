import 'package:finance_app/features/auth/data/datasources/session_client.dart';
import 'package:finance_app/features/auth/domain/entities/otp_challenge.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);
  final SessionClient _client;

  Future<Map<String, dynamic>> _public(String path, Map<String, dynamic> body) =>
      _client.send('POST', '/auth$path', body: body, auth: false);

  Future<OtpChallenge> login(String email, String password) async =>
      OtpChallenge.fromJson(await _public('/login', {'email': email, 'password': password}), email: email);

  Future<OtpChallenge> register(String name, String email, String password) async =>
      OtpChallenge.fromJson(await _public('/register', {'name': name, 'email': email, 'password': password}),
          email: email);

  Future<Map<String, dynamic>> verifyOtp(OtpChallenge challenge, String code) =>
      _public('/verify-otp', {'otpToken': challenge.token, 'code': code});

  Future<OtpChallenge> resendOtp(OtpChallenge challenge) async =>
      challenge.resent(await _public('/resend-otp', {'otpToken': challenge.token}));

  Future<String?> forgotPassword(String email) async =>
      (await _public('/forgot-password', {'email': email}))['devCode'] as String?;

  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) =>
      _public('/reset-password', {'email': email, 'code': code, 'newPassword': newPassword});

  Future<Map<String, dynamic>> changePassword(String oldPassword, String newPassword) =>
      _client.send('PUT', '/auth/change-password', body: {'oldPassword': oldPassword, 'newPassword': newPassword});

  Future<void> verifyEmail(String code) => _client.send('POST', '/auth/verify-email', body: {'code': code});

  Future<String?> resendVerification() async =>
      (await _client.send('POST', '/auth/resend-verification'))['devCode'] as String?;

  Future<void> updateProfile(Map<String, dynamic> profile) => _client.send('PUT', '/auth/me', body: profile);

  Future<void> logout({required bool everywhere, String? refreshToken}) =>
      _client.send('POST', '/auth/logout', body: everywhere ? {'all': true} : {'refreshToken': refreshToken});

  Future<void> deleteAccount(String password) => _client.send('DELETE', '/auth/me', body: {'password': password});
}
