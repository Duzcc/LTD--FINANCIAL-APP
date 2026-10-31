import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/auth/presentation/forgot_password_screen.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
String? validateEmail(String? v) =>
    _emailPattern.hasMatch((v ?? '').trim()) ? null : 'Email không hợp lệ';
String? validatePassword(String? v) =>
    (v ?? '').length < 6 ? 'Mật khẩu tối thiểu 6 ký tự' : null;

/// Sau khi đăng nhập thành công: hỏi cách xử lý dữ liệu nếu cần rồi vào ứng dụng.
Future<void> finishSignIn(BuildContext context, bool needsDecision,
    {required bool fromSettings}) async {
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
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Hủy')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Gộp lên tài khoản')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Dùng dữ liệu tài khoản')),
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
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()), (_) => false);
  }
}

/// Chọn địa chỉ backend (máy chủ API chạy độc lập với ứng dụng).
Future<void> editServer(BuildContext context) async {
  final p = context.read<FinanceProvider>();
  final controller = TextEditingController(text: p.serverUrl);
  String? status;
  bool checking = false;
  final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
                  title: const Text('Máy chủ API'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            controller: controller,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                                labelText: 'Địa chỉ backend',
                                hintText: 'https://api.ten-mien.vn')),
                        const SizedBox(height: 8),
                        Text(
                            'Mặc định: ${ApiClient.defaultBaseUrl}. Máy ảo Android dùng 10.0.2.2 để gọi máy tính.',
                            style: const TextStyle(fontSize: 12)),
                        if (status != null) ...[
                          const SizedBox(height: 10),
                          Text(status!,
                              style: TextStyle(
                                  color: status == 'Kết nối thành công'
                                      ? AppColors.primaryGreen
                                      : AppColors.accentRed)),
                        ]
                      ]),
                  actions: [
                    TextButton(
                        onPressed: checking
                            ? null
                            : () async {
                                setDialog(() => checking = true);
                                final error = await p.checkServer(
                                    ApiClient.normalize(controller.text));
                                if (!ctx.mounted) return;
                                setDialog(() {
                                  checking = false;
                                  status = error ?? 'Kết nối thành công';
                                });
                              },
                        child: Text(checking ? 'Đang kiểm tra…' : 'Kiểm tra')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, controller.text),
                        child: const Text('Lưu')),
                  ])));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  if (saved != null) p.setServerUrl(saved);
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.fromSettings = false});

  /// Mở từ mục Tài khoản (đang dùng ngoại tuyến) thay vì màn hình đầu tiên.
  final bool fromSettings;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      offlineName = TextEditingController();
  bool registering = false, busy = false, showPassword = false;
  String? error;

  @override
  void dispose() {
    for (final c in [name, email, password, confirm, offlineName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final p = context.read<FinanceProvider>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final needs = registering
          ? await p.register(
              name: name.text, email: email.text, password: password.text)
          : await p.signIn(email: email.text, password: password.text);
      if (!mounted) return;
      await finishSignIn(context, needs, fromSettings: widget.fromSettings);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return Scaffold(
        appBar: widget.fromSettings
            ? AppBar(title: const Text('Đăng nhập tài khoản'))
            : null,
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                        key: form,
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                            children: [
                              if (!widget.fromSettings) ...[
                                const Align(
                                    alignment: Alignment.centerLeft,
                                    child: CircleAvatar(
                                        radius: 36,
                                        backgroundColor: Color(0xFFE6D8CB),
                                        child: Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            size: 34,
                                            color: Color(0xFF917560)))),
                                const SizedBox(height: 24),
                                const Text('Tiền của bạn.\nKế hoạch của bạn.',
                                    style: TextStyle(
                                        fontSize: 30,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: 10),
                                const Text(
                                    'Ghi chép thu chi, quản lý ví và từng bước đạt mục tiêu tiết kiệm.',
                                    style: TextStyle(fontSize: 15, height: 1.5)),
                                const SizedBox(height: 24),
                              ],
                              SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                        value: false, label: Text('Đăng nhập')),
                                    ButtonSegment(
                                        value: true, label: Text('Đăng ký')),
                                  ],
                                  selected: {registering},
                                  onSelectionChanged: (v) => setState(() {
                                        registering = v.first;
                                        error = null;
                                      })),
                              const SizedBox(height: 20),
                              if (registering) ...[
                                TextFormField(
                                    controller: name,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                        labelText: 'Họ và tên',
                                        prefixIcon: Icon(Icons.person_outline)),
                                    validator: (v) =>
                                        (v ?? '').trim().isEmpty
                                            ? 'Vui lòng nhập họ tên'
                                            : null),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                  key: const ValueKey('auth-email'),
                                  controller: email,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(Icons.mail_outline)),
                                  validator: validateEmail),
                              const SizedBox(height: 12),
                              TextFormField(
                                  key: const ValueKey('auth-password'),
                                  controller: password,
                                  obscureText: !showPassword,
                                  decoration: InputDecoration(
                                      labelText: 'Mật khẩu',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                          tooltip: showPassword
                                              ? 'Ẩn mật khẩu'
                                              : 'Hiện mật khẩu',
                                          onPressed: () => setState(() =>
                                              showPassword = !showPassword),
                                          icon: Icon(showPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined))),
                                  validator: validatePassword,
                                  onFieldSubmitted: (_) =>
                                      registering ? null : submit()),
                              if (registering) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: confirm,
                                    obscureText: !showPassword,
                                    decoration: const InputDecoration(
                                        labelText: 'Nhập lại mật khẩu',
                                        prefixIcon: Icon(Icons.lock_outline)),
                                    validator: (v) => v != password.text
                                        ? 'Mật khẩu nhập lại không khớp'
                                        : null),
                              ],
                              if (error != null) ...[
                                const SizedBox(height: 12),
                                Text(error!,
                                    style: const TextStyle(
                                        color: AppColors.accentRed)),
                              ],
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: busy ? null : submit,
                                  child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: busy
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))
                                          : Text(registering
                                              ? 'Tạo tài khoản'
                                              : 'Đăng nhập'))),
                              if (!registering)
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                        onPressed: () => openPage(
                                            context,
                                            ForgotPasswordScreen(
                                                email: email.text,
                                                fromSettings:
                                                    widget.fromSettings)),
                                        child: const Text('Quên mật khẩu?'))),
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  tileColor: Colors.transparent,
                                  leading: const Icon(Icons.dns_outlined),
                                  title: const Text('Máy chủ',
                                      style: TextStyle(fontSize: 13)),
                                  subtitle: Text(p.serverUrl,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: const Icon(Icons.edit_outlined,
                                      size: 18),
                                  onTap: () => editServer(context)),
                              if (!widget.fromSettings) ...[
                                const SizedBox(height: 8),
                                const Row(children: [
                                  Expanded(child: Divider()),
                                  Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 12),
                                      child: Text('hoặc')),
                                  Expanded(child: Divider()),
                                ]),
                                const SizedBox(height: 16),
                                TextField(
                                    controller: offlineName,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                        labelText: 'Bạn muốn được gọi là gì?',
                                        hintText: 'Tên của bạn',
                                        prefixIcon:
                                            Icon(Icons.badge_outlined))),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                    onPressed: () {
                                      p.preferences(
                                          name: offlineName.text.isEmpty
                                              ? 'Bạn'
                                              : offlineName.text);
                                      Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const MainScreen()));
                                    },
                                    child: const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Text('Bắt đầu sử dụng'))),
                                const SizedBox(height: 10),
                                const Text(
                                    'Dùng ngoại tuyến: dữ liệu chỉ lưu trên thiết bị. Bạn có thể đăng nhập sau trong mục Tài khoản để sao lưu và đồng bộ.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, height: 1.5)),
                              ],
                            ]))))));
  }
}
