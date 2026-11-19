import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/auth/presentation/screens/auth_screen.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.challenge, this.fromSettings = false});
  final OtpChallenge challenge;
  final bool fromSettings;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with BusyState {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  late OtpChallenge challenge = widget.challenge;
  late DateTime expiresAt, resendAt;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    restartClock();
  }

  @override
  void dispose() {
    ticker?.cancel();
    code.dispose();
    super.dispose();
  }

  void restartClock() {
    final now = DateTime.now();
    expiresAt = now.add(Duration(seconds: challenge.expiresIn));
    resendAt = now.add(Duration(seconds: challenge.resendAfter));
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (secondsUntil(expiresAt) == 0 && secondsUntil(resendAt) == 0) t.cancel();
    });
  }

  int secondsUntil(DateTime t) {
    final s = t.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s;
  }

  String clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  void leave(String reason) {
    message(context, reason);
    Navigator.pop(context);
  }

  Future<void> verify() async {
    if (busy || !form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    final failure = await runBusy(() async {
      final needs = await p.verifyOtp(challenge, code.text);
      if (!mounted) return;
      ticker?.cancel();
      await finishSignIn(context, needs, fromSettings: widget.fromSettings);
    });
    if (failure == null || !mounted) return;
    if (_expired(failure)) return leave('$failure');
    code.clear();
  }

  bool _expired(Object failure) => failure is ApiException && failure.code == 'OTP_EXPIRED';

  Future<void> resend() async {
    final p = context.read<FinanceProvider>();
    final failure = await runBusy(() async {
      final next = await p.resendOtp(challenge);
      if (!mounted) return;
      setState(() {
        challenge = next;
        restartClock();
        code.clear();
      });
      message(context, 'Đã gửi lại mã OTP tới ${challenge.email}.');
    });
    if (failure != null && mounted && _expired(failure)) leave('$failure');
  }

  @override
  Widget build(BuildContext context) {
    final left = secondsUntil(expiresAt), wait = secondsUntil(resendAt);
    final expired = left == 0;
    return FinancePage(
        title: challenge.isRegister ? 'Xác thực email' : 'Xác thực đăng nhập',
        child: Form(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            key: form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const Icon(Icons.mark_email_read_outlined, size: 56, color: AppColors.primaryGreen),
              const SizedBox(height: 16),
              Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Mã OTP gồm 6 chữ số đã được gửi tới '),
                    TextSpan(text: challenge.email, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: challenge.isRegister ? '. Nhập mã để hoàn tất đăng ký.' : '. Nhập mã để đăng nhập.'),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5)),
              if (kDebugMode && challenge.devCode != null) ...[
                const SizedBox(height: 12),
                Panel(
                    color: AppColors.primaryGreenSurface,
                    child: Text('Mã OTP của bạn: ${challenge.devCode}', style: const TextStyle(height: 1.5))),
              ],
              const SizedBox(height: 20),
              TextFormField(
                  key: const ValueKey('otp-code'),
                  controller: code,
                  autofocus: true,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                  validator: validateOtp,
                  onChanged: (v) {
                    if (v.length == 6 && !expired) verify();
                  }),
              const SizedBox(height: 8),
              Text(expired ? 'Mã đã hết hạn, hãy gửi lại mã mới.' : 'Mã hết hạn sau ${clock(left)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: expired ? AppColors.accentRed : null)),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.accentRed)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: busy || expired ? null : verify,
                  child: Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'Đang xác thực…' : 'Xác nhận'))),
              TextButton(
                  onPressed: busy || wait > 0 ? null : resend,
                  child: Text(wait > 0 ? 'Gửi lại mã sau ${wait}s' : 'Gửi lại mã')),
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Đổi email / quay lại')),
            ])));
  }
}
