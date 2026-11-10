class AccountSession {
  const AccountSession(
      {required this.baseUrl,
      required this.token,
      required this.email,
      required this.userId,
      this.refreshToken,
      this.emailVerified = true});
  final String baseUrl, token, email, userId;
  final String? refreshToken;
  final bool emailVerified;

  AccountSession withToken(String value, {String? refresh, bool? verified}) =>
      AccountSession(
          baseUrl: baseUrl,
          token: value,
          email: email,
          userId: userId,
          refreshToken: refresh ?? refreshToken,
          emailVerified: verified ?? emailVerified);

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'token': token,
        'email': email,
        'userId': userId,
        'refreshToken': refreshToken,
        'emailVerified': emailVerified
      };

  static AccountSession? fromJson(Object? j, {required String defaultBaseUrl}) {
    if (j is! Map) return null;
    final token = j['token'];
    if (token is! String || token.isEmpty) return null;
    return AccountSession(
        baseUrl: '${j['baseUrl'] ?? defaultBaseUrl}',
        token: token,
        email: '${j['email'] ?? ''}',
        userId: '${j['userId'] ?? ''}',
        refreshToken: j['refreshToken'] as String?,
        emailVerified: j['emailVerified'] != false);
  }
}
