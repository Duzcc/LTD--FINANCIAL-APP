import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.email = ''});
  final String email;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with BusyState {
  final form = GlobalKey<FormState>();
  late final email = TextEditingController(text: widget.email);
  bool requested = false;
  bool? registered;
  bool? verified;
  String? hint;
  String? devLink;

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function(FinanceProvider p) action) async {
    if (!form.currentState!.validate()) return;
    await runBusy(() => action(context.read<FinanceProvider>()));
  }

  Future<void> sendLink(FinanceProvider p) async {
    final result = await p.forgotPassword(email.text.trim());
    if (!mounted) return;
    setState(() {
      registered = result['registered'] as bool?;
      verified = result['verified'] as bool?;
      requested = result['mailEnabled'] == true;
      devLink = result['devLink'] as String?;
      hint = result['message'] as String?;
    });
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Quên mật khẩu',
      child: Form(
          autovalidateMode: AutovalidateMode.disabled,
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Nhập email đã đăng ký. Một liên kết an toàn sẽ được gửi để bạn đặt mật khẩu mới.',
                style: TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.mail_outline),
                ),
                validator: validateLoginEmail),
            if (hint != null) ...[
              const SizedBox(height: 12),
              if (registered == false || (registered == true && verified == false))
                Text(hint!, style: const TextStyle(color: AppColors.accentRed, height: 1.5))
              else
                Panel(color: AppColors.primaryGreenSurface, child: Text(hint!, style: const TextStyle(height: 1.5))),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            const SizedBox(height: 20),
            FilledButton(
                onPressed: busy ? null : () => run(sendLink),
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(busy
                        ? 'Đang gửi…'
                        : requested
                            ? 'Gửi lại liên kết'
                            : 'Gửi liên kết đặt lại mật khẩu'))),
            if (devLink != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText('Liên kết kiểm tra: $devLink'),
              ),
          ])));
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> with BusyState {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(), next = TextEditingController(), confirm = TextEditingController();
  @override
  void dispose() {
    for (final c in [current, next, confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final failure = await runBusy(() => context.read<FinanceProvider>().changePassword(current.text, next.text));
    if (failure != null || !mounted) return;
    message(context, 'Đã đổi mật khẩu.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Đổi mật khẩu',
      child: Form(
          autovalidateMode: AutovalidateMode.disabled,
          key: form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: current,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Mật khẩu hiện tại', prefixIcon: const Icon(Icons.lock_outline)),
                validator: (v) => (v ?? '').isEmpty ? 'Nhập mật khẩu hiện tại' : null),
            const SizedBox(height: 12),
            TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: next,
                obscureText: true,
                maxLength: 72,
                decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    helperText: passwordRules,
                    counterText: '',
                    prefixIcon: const Icon(Icons.lock_outline)),
                validator: (v) =>
                    validatePassword(v, email: context.read<FinanceProvider>().session?.email) ??
                    (v == current.text ? 'Mật khẩu mới phải khác mật khẩu hiện tại' : null)),
            const SizedBox(height: 12),
            TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                controller: confirm,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: 'Nhập lại mật khẩu mới', prefixIcon: const Icon(Icons.lock_reset)),
                validator: (v) => v != next.text ? 'Mật khẩu nhập lại không khớp' : null),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            const SizedBox(height: 20),
            FilledButton(
                onPressed: busy ? null : save,
                child:
                    Padding(padding: const EdgeInsets.all(14), child: Text(busy ? 'Đang lưu…' : 'Lưu mật khẩu mới'))),
          ])));
}
