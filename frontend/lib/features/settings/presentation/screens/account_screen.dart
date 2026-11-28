import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallets_screen.dart';
import 'package:finance_app/features/categories/presentation/screens/select_category_screen.dart';
import 'package:finance_app/features/categories/presentation/screens/select_person_screen.dart';
import 'package:finance_app/features/auth/presentation/screens/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/screens/forgot_password_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return FinancePage(
        title: 'Tài khoản',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const AccountCard(),
          const SectionTitle('QUẢN LÝ'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(context, Icons.account_balance_wallet_outlined, 'Cài đặt ví',
                    () => openPage(context, const WalletsScreen())),
                const Divider(indent: 60),
                _row(context, Icons.category_outlined, 'Cài đặt danh mục',
                    () => openPage(context, const SelectCategoryScreen(manage: true))),
                const Divider(indent: 60),
                _row(context, Icons.people_outline, 'Đối tượng',
                    () => openPage(context, const SelectPersonScreen(manage: true))),
              ])),
          const SectionTitle('BẢO MẬT'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                if (p.signedIn) ...[
                  _row(
                      context, Icons.lock_reset, 'Đổi mật khẩu', () => openPage(context, const ChangePasswordScreen())),
                  const Divider(indent: 60),
                  ListTile(
                      leading: const RoundIcon(Icons.logout, color: AppColors.accentRed),
                      title: const Text('Đăng xuất', style: TextStyle(color: AppColors.accentRed)),
                      onTap: () => signOutFlow(context)),
                  const Divider(indent: 60),
                  _row(context, Icons.person_remove_outlined, 'Xóa tài khoản', () => deleteAccountFlow(context)),
                ] else
                  _row(context, Icons.login, 'Đăng nhập / Đăng ký',
                      () => openPage(context, const AuthScreen(fromSettings: true))),
              ])),
          const SizedBox(height: 24),
          const Center(child: Text('Quản lý chi tiêu • Nhóm 03', style: TextStyle(fontSize: 12))),
        ]));
  }

  Widget _row(BuildContext context, IconData icon, String title, VoidCallback onTap) => ListTile(
      leading: RoundIcon(icon), title: Text(title), trailing: const Icon(Icons.chevron_right, size: 20), onTap: onTap);
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return Panel(
        color: const Color(0xFFDDC7B6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF806B5D),
                foregroundColor: Colors.white,
                child: Text(p.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(p.signedIn ? p.session!.email : 'Chưa đăng nhập', maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            IconButton(
                tooltip: 'Đổi tên hiển thị',
                onPressed: () async {
                  final name = await editText(context, 'Tên hiển thị', initial: p.displayName, validator: validateName);
                  if (name != null) p.preferences(name: name);
                },
                icon: const Icon(Icons.edit_outlined)),
          ]),
          if (!p.signedIn) ...[
            const SizedBox(height: 12),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => openPage(context, const AuthScreen(fromSettings: true)),
                    child: const Text('Đăng nhập'))),
          ],
        ]));
  }
}

Future<void> signOutFlow(BuildContext context) async {
  final p = context.read<FinanceProvider>();
  if (p.pendingChanges > 0) await p.syncNow(pull: false);
  if (!context.mounted) return;
  final pending = p.pendingChanges;
  final ok = await confirmAction(context,
      title: 'Đăng xuất?',
      content: pending > 0
          ? 'Còn $pending thay đổi chưa đồng bộ được và sẽ bị mất khi đăng xuất. Dữ liệu trên điện thoại này sẽ được xóa.'
          : 'Dữ liệu đã được đồng bộ với tài khoản. Dữ liệu trên điện thoại này sẽ được xóa.',
      confirm: 'Đăng xuất',
      danger: pending > 0);
  if (!ok || !context.mounted) return;
  await p.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
}

Future<void> deleteAccountFlow(BuildContext context) async {
  final p = context.read<FinanceProvider>();
  final password = await editText(context, 'Nhập mật khẩu để xóa tài khoản', obscure: true);
  if (password == null || !context.mounted) return;
  final ok = await confirmAction(context,
      title: 'Xóa vĩnh viễn tài khoản?',
      content:
          'Toàn bộ ví, giao dịch, danh mục, đối tượng và ngân sách của tài khoản sẽ bị xóa và không thể khôi phục.',
      confirm: 'Xóa tài khoản',
      danger: true);
  if (!ok || !context.mounted) return;
  await attempt(context, () async {
    await p.deleteAccount(password);
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  });
}
