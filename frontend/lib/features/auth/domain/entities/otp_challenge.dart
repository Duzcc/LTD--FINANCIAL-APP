class OtpChallenge {
  const OtpChallenge(
      {required this.token,
      required this.email,
      this.purpose = 'login',
      this.devCode,
      this.expiresIn = 300,
      this.resendAfter = 60});
  final String token, email, purpose;
  final String? devCode;
  final int expiresIn, resendAfter;

  bool get isRegister => purpose == 'register';

  factory OtpChallenge.fromJson(Map<String, dynamic> j, {String email = ''}) => OtpChallenge(
      token: '${j['otpToken']}',
      email: '${j['email'] ?? email}',
      purpose: '${j['purpose'] ?? 'login'}',
      devCode: j['devCode'] as String?,
      expiresIn: (j['expiresIn'] as num?)?.toInt() ?? 300,
      resendAfter: (j['resendAfter'] as num?)?.toInt() ?? 60);

  OtpChallenge resent(Map<String, dynamic> j) => OtpChallenge(
      token: token,
      email: email,
      purpose: purpose,
      devCode: j['devCode'] as String?,
      expiresIn: (j['expiresIn'] as num?)?.toInt() ?? expiresIn,
      resendAfter: (j['resendAfter'] as num?)?.toInt() ?? resendAfter);
}
