import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/brand_logo.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/features/auth/presentation/screens/forgot_password_screen.dart';

Future<void> finishSignIn(BuildContext context, bool needsDecision, {required bool fromSettings}) async {
  final p = context.read<FinanceProvider>();
  if (needsDecision) {
    final useAccount = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
                title: const Text('Chọn dữ liệu sử dụng'),
                content: const Text(
                    'Thiết bị này và tài khoản đều đã có dữ liệu. Bạn muốn dùng dữ liệu của tài khoản (dữ liệu trên máy sẽ được thay thế) hay gộp dữ liệu máy này lên tài khoản?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Gộp lên tài khoản')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dùng dữ liệu tài khoản')),
                ]));
    if (useAccount == null) {
      p.cancelLogin();
      return;
    }
    await p.resolveLogin(useAccount: useAccount);
  }
  if (!context.mounted) return;
  if (p.syncError != null) message(context, p.syncError!);
  if (fromSettings) {
    Navigator.of(context).popUntil((r) => r.isFirst);
  } else {
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.fromSettings = false, this.successMessage});

  final bool fromSettings;
  final String? successMessage;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with BusyState {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool registering = false, showPassword = false;

  @override
  void dispose() {
    for (final c in [name, email, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    await runBusy(() async {
      if (registering) {
        final result = await p.register(name: name.text, email: email.text, password: password.text);
        final address = email.text.trim().toLowerCase();
        final devLink = result['devLink'] as String?;
        if (!mounted) return;
        password.clear();
        confirm.clear();
        await openPage(
          context,
          VerificationPendingScreen(
            email: address,
            devLink: devLink,
            onBackToLogin: () => setState(() => registering = false),
          ),
        );
        return;
      }
      final needsDecision = await p.signIn(email: email.text, password: password.text);
      if (!mounted) return;
      password.clear();
      confirm.clear();
      await finishSignIn(context, needsDecision, fromSettings: widget.fromSettings);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: widget.fromSettings ? AppBar(title: const Text('Đăng nhập tài khoản')) : null,
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                        autovalidateMode: AutovalidateMode.disabled,
                        key: form,
                        child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 32), children: [
                          if (!widget.fromSettings) ...[
                            const Align(alignment: Alignment.centerLeft, child: BrandLogo.app(size: 76)),
                            const SizedBox(height: 24),
                            const Text('Tiền của bạn.\nKế hoạch của bạn.',
                                style: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 10),
                            const Text('Ghi chép thu chi, quản lý ví và từng bước đạt mục tiêu tiết kiệm.',
                                style: TextStyle(fontSize: 15, height: 1.5)),
                            const SizedBox(height: 24),
                          ],
                          SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('Đăng nhập')),
                                ButtonSegment(value: true, label: Text('Đăng ký')),
                              ],
                              selected: {
                                registering
                              },
                              onSelectionChanged: (v) => setState(() {
                                    registering = v.first;
                                    error = null;
                                    form.currentState?.reset();
                                  })),
                          if (widget.successMessage != null) ...[
                            const SizedBox(height: 12),
                            Panel(
                              color: AppColors.primaryGreenSurface,
                              child: Text(widget.successMessage!, style: const TextStyle(height: 1.5)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (registering) ...[
                            TextFormField(
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                controller: name,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 50,
                                decoration: InputDecoration(
                                    labelText: 'Họ và tên',
                                    counterText: '',
                                    prefixIcon: const Icon(Icons.person_outline)),
                                validator: validateName),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                              key: const ValueKey('auth-email'),
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              maxLength: 254,
                              autofillHints: const [AutofillHints.email],
                              decoration: InputDecoration(
                                  counterText: '', labelText: 'Email', prefixIcon: const Icon(Icons.mail_outline)),
                              validator: (v) => registering ? validateEmail(v) : validateLoginEmail(v)),
                          const SizedBox(height: 12),
                          TextFormField(
                              key: const ValueKey('auth-password'),
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              controller: password,
                              obscureText: !showPassword,
                              textInputAction: registering ? TextInputAction.next : TextInputAction.done,
                              maxLength: 72,
                              decoration: InputDecoration(
                                  labelText: 'Mật khẩu',
                                  counterText: '',
                                  helperText: registering ? passwordRules : null,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                      tooltip: showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                                      onPressed: () => setState(() => showPassword = !showPassword),
                                      icon: Icon(
                                          showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined))),
                              validator: (v) =>
                                  registering ? validatePassword(v, email: email.text) : validateLoginPassword(v),
                              onFieldSubmitted: (_) => registering ? null : submit()),
                          if (registering) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                controller: confirm,
                                obscureText: !showPassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => submit(),
                                decoration: InputDecoration(
                                    labelText: 'Nhập lại mật khẩu', prefixIcon: const Icon(Icons.lock_reset)),
                                validator: (v) => (v ?? '').isEmpty
                                    ? 'Vui lòng nhập lại mật khẩu'
                                    : v != password.text
                                        ? 'Mật khẩu nhập lại không khớp'
                                        : null),
                          ],
                          if (error != null) ...[
                            const SizedBox(height: 12),
                            Text(error!, style: const TextStyle(color: AppColors.accentRed)),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: busy ? null : submit,
                              child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: busy
                                      ? const SizedBox.square(
                                          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Text(registering ? 'Tạo tài khoản' : 'Đăng nhập'))),
                          if (!registering)
                            Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                    onPressed: () => openPage(context, ForgotPasswordScreen(email: email.text)),
                                    child: const Text('Quên mật khẩu?'))),
                        ]))))));
  }
}

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key, required this.email, required this.onBackToLogin, this.devLink});
  final String email;
  final String? devLink;
  final VoidCallback onBackToLogin;

  @override
  State<VerificationPendingScreen> createState() => _VerificationPendingScreenState();
}

class _VerificationPendingScreenState extends State<VerificationPendingScreen> with BusyState {
  String? devLink;

  @override
  void initState() {
    super.initState();
    devLink = widget.devLink;
  }

  Future<void> resend() async {
    await runBusy(() async {
      final result = await context.read<FinanceProvider>().resendVerification(widget.email);
      if (!mounted) return;
      setState(() => devLink = result['devLink'] as String?);
      message(context, 'Nếu tài khoản chưa xác minh, liên kết mới đã được gửi tới email.');
    });
  }

  @override
  Widget build(BuildContext context) => FinancePage(
        title: 'Xác minh email',
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Icon(Icons.mark_email_read_outlined, size: 56, color: AppColors.primaryGreen),
          const SizedBox(height: 16),
          Text(
            'Mở email gửi tới ${widget.email} và nhấn nút xác nhận. Ứng dụng sẽ tự mở và đưa bạn về màn hình đăng nhập.',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          if (kDebugMode && devLink != null) ...[
            const SizedBox(height: 16),
            Panel(
              color: AppColors.primaryGreenSurface,
              child: SelectableText('Liên kết kiểm tra: $devLink', style: const TextStyle(height: 1.5)),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : resend,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(busy ? 'Đang gửi…' : 'Gửi lại liên kết'),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onBackToLogin();
            },
            child: const Text('Quay lại đăng nhập'),
          ),
        ]),
      );
}
