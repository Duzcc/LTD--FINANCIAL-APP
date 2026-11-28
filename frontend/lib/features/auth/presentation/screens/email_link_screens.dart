import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.token});
  final String token;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> with BusyState {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_verifyEmail());
    });
  }

  Future<void> _verifyEmail() async {
    final failure = await runBusy(() => context.read<FinanceProvider>().verifyEmail(widget.token));
    if (failure != null || !mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (_) => false,
      arguments: 'Email đã được xác minh. Mời bạn đăng nhập.',
    );
  }

  void _backToLogin() => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);

  @override
  Widget build(BuildContext context) => FinancePage(
        title: 'Xác minh email',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Đang xác minh email…'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.accentRed)),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _backToLogin, child: const Text('Về đăng nhập')),
                    ],
                  ),
          ),
        ),
      );
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});
  final String token;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with BusyState {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool validating = true;
  bool tokenValid = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_validateToken());
    });
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> _validateToken() async {
    final failure = await runBusy(() => context.read<FinanceProvider>().validateResetToken(widget.token));
    if (!mounted) return;
    setState(() {
      validating = false;
      tokenValid = failure == null;
    });
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final provider = context.read<FinanceProvider>();
    final failure = await runBusy(() async {
      await provider.resetPassword(widget.token, password.text, confirm.text);
      if (provider.signedIn) await provider.signOut(revoke: false);
    });
    if (failure != null || !mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.login,
      (_) => false,
      arguments: 'Mật khẩu đã được đặt lại. Hãy đăng nhập bằng mật khẩu mới.',
    );
  }

  void _backToLogin() => Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);

  @override
  Widget build(BuildContext context) => FinancePage(
        title: 'Đặt lại mật khẩu',
        child: validating
            ? const Center(child: CircularProgressIndicator())
            : !tokenValid
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error ?? 'Liên kết không hợp lệ hoặc đã hết hạn.',
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.accentRed)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _backToLogin, child: const Text('Về đăng nhập')),
                        ],
                      ),
                    ),
                  )
                : Form(
                    key: form,
                    autovalidateMode: AutovalidateMode.disabled,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text('Nhập mật khẩu mới và xác nhận để hoàn tất.', style: TextStyle(height: 1.5)),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('reset-new-password'),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          controller: password,
                          obscureText: true,
                          maxLength: 72,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu mới',
                            helperText: passwordRules,
                            counterText: '',
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                          validator: validatePassword,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('reset-confirm-password'),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          controller: confirm,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Xác nhận mật khẩu mới',
                            prefixIcon: const Icon(Icons.lock_reset),
                          ),
                          validator: (value) => value != password.text ? 'Mật khẩu nhập lại không khớp' : null,
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(error!, style: const TextStyle(color: AppColors.accentRed)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: busy ? null : _save,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(busy ? 'Đang lưu…' : 'Xác nhận mật khẩu mới'),
                          ),
                        ),
                      ],
                    ),
                  ),
      );
}
