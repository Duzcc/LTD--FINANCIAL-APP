import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';

/// Quên mật khẩu: bước 1 nhận mã qua email, bước 2 nhập mã và mật khẩu mới.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen(
      {super.key, this.email = '', this.fromSettings = false});
  final String email;
  final bool fromSettings;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final form = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.email);
  final code = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool codeSent = false, busy = false;
  String? error, hint;

  @override
  void dispose() {
    for (final c in [email, code, password, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function(FinanceProvider p) action) async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action(context.read<FinanceProvider>());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendCode(FinanceProvider p) async {
    final dev = await p.forgotPassword(email.text);
    if (!mounted) return;
    setState(() {
      codeSent = true;
      hint = dev == null
          ? 'Nếu email đã đăng ký, mã gồm 6 chữ số đã được gửi tới hộp thư. Mã có hiệu lực 15 phút.'
          : 'Máy chủ đang ở chế độ thử nghiệm (chưa cấu hình email). Mã khôi phục: $dev';
    });
  }

  Future<void> reset(FinanceProvider p) async {
    final needs = await p.resetPassword(
        email: email.text, code: code.text, newPassword: password.text);
    if (!mounted) return;
    message(context, 'Đã đặt lại mật khẩu.');
    await finishSignIn(context, needs, fromSettings: widget.fromSettings);
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Quên mật khẩu',
      child: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(
                codeSent
                    ? 'Nhập mã khôi phục và mật khẩu mới.'
                    : 'Nhập email đã đăng ký để nhận mã khôi phục mật khẩu.',
                style: const TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            TextFormField(
                controller: email,
                enabled: !codeSent,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                validator: validateEmail),
            if (hint != null) ...[
              const SizedBox(height: 12),
              Panel(
                  color: AppColors.primaryGreenSurface,
                  child: Text(hint!, style: const TextStyle(height: 1.5))),
            ],
            if (codeSent) ...[
              const SizedBox(height: 12),
              TextFormField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'Mã khôi phục (6 số)',
                      prefixIcon: Icon(Icons.pin_outlined)),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => validateOtp(v) == null
                      ? null
                      : 'Mã khôi phục gồm đúng 6 chữ số'),
              const SizedBox(height: 4),
              TextFormField(
                  controller: password,
                  obscureText: true,
                  maxLength: 72,
                  decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới',
                      helperText: passwordRules,
                      counterText: '',
                      prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => validatePassword(v, email: email.text)),
              const SizedBox(height: 12),
              TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Nhập lại mật khẩu mới',
                      prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) =>
                      v != password.text ? 'Mật khẩu nhập lại không khớp' : null),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            const SizedBox(height: 20),
            FilledButton(
                onPressed: busy ? null : () => run(codeSent ? reset : sendCode),
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(busy
                        ? 'Đang xử lý…'
                        : codeSent
                            ? 'Đặt lại mật khẩu'
                            : 'Gửi mã khôi phục'))),
            if (codeSent)
              TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            codeSent = false;
                            hint = null;
                          }),
                  child: const Text('Gửi lại mã / đổi email')),
          ])));
}

/// Đổi mật khẩu: xác thực bằng mật khẩu hiện tại.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      next = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in [current, next, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await context
          .read<FinanceProvider>()
          .changePassword(current.text, next.text);
      if (!mounted) return;
      message(context, 'Đã đổi mật khẩu. Các thiết bị khác cần đăng nhập lại.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Đổi mật khẩu',
      child: Form(
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                    prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Nhập mật khẩu hiện tại' : null),
            const SizedBox(height: 12),
            TextFormField(
                controller: next,
                obscureText: true,
                maxLength: 72,
                decoration: const InputDecoration(
                    labelText: 'Mật khẩu mới',
                    helperText: passwordRules,
                    counterText: '',
                    prefixIcon: Icon(Icons.lock_reset)),
                validator: (v) => validatePassword(v,
                        email: context.read<FinanceProvider>().session?.email) ??
                    (v == current.text
                        ? 'Mật khẩu mới phải khác mật khẩu hiện tại'
                        : null)),
            const SizedBox(height: 12),
            TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu mới',
                    prefixIcon: Icon(Icons.lock_reset)),
                validator: (v) =>
                    v != next.text ? 'Mật khẩu nhập lại không khớp' : null),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            const SizedBox(height: 20),
            FilledButton(
                onPressed: busy ? null : save,
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(busy ? 'Đang lưu…' : 'Lưu mật khẩu mới'))),
          ])));
}
