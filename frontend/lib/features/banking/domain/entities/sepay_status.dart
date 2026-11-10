class SepayStatus {
  const SepayStatus(
      {required this.connected,
      required this.webhookUrl,
      this.keyHint,
      this.apiKey,
      this.pollingEnabled = false,
      this.pollSeconds = 15});
  final bool connected;

  final bool pollingEnabled;
  final int pollSeconds;
  final String webhookUrl;
  final String? keyHint;

  final String? apiKey;
  factory SepayStatus.fromJson(Map<String, dynamic> j) => SepayStatus(
      connected: j['connected'] == true || j['apiKey'] != null,
      webhookUrl: '${j['webhookUrl'] ?? ''}',
      keyHint: j['keyHint'] as String?,
      apiKey: j['apiKey'] as String?,
      pollingEnabled: j['pollingEnabled'] == true,
      pollSeconds: (j['pollSeconds'] as num?)?.toInt() ?? 15);
}
