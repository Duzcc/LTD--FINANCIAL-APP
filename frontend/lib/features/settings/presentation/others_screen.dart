import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/wallets_screen.dart';
import 'package:finance_app/features/wallets/presentation/currency_selection_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_person_screen.dart';
import 'package:finance_app/features/statistics/presentation/statistics_screen.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/features/settings/presentation/settings_screens.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/features/settings/data/excel_export.dart';

class OthersScreen extends StatelessWidget {
  const OthersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return FinancePage(
        title: 'Tài khoản',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const AccountCard(),
          const SectionTitle('TRỢ LÝ AI'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(context, Icons.chat_bubble_outline, 'Hỏi trợ lý tài chính',
                    () => openPage(context, const AssistantScreen())),
                const Divider(indent: 60),
                _row(context, Icons.auto_awesome, 'Phân tích & dự báo',
                    () => openPage(context, const InsightsScreen())),
                const Divider(indent: 60),
                _row(context, Icons.edit_note, 'Nhập nhanh bằng câu',
                    () => showQuickEntry(context)),
              ])),
          const SectionTitle('QUẢN LÝ'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(
                    context,
                    Icons.account_balance_wallet_outlined,
                    'Cài đặt ví',
                    () => openPage(context, const WalletsScreen())),
                const Divider(indent: 60),
                _row(
                    context,
                    Icons.category_outlined,
                    'Cài đặt danh mục',
                    () => openPage(
                        context, const SelectCategoryScreen(manage: true))),
                const Divider(indent: 60),
                _row(
                    context,
                    Icons.people_outline,
                    'Đối tượng',
                    () => openPage(
                        context, const SelectPersonScreen(manage: true))),
                const Divider(indent: 60),
                _row(context, Icons.pie_chart_outline, 'Báo cáo thống kê',
                    () => openPage(context, const StatisticsScreen())),
                const Divider(indent: 60),
                _row(context, Icons.event_repeat, 'Giao dịch định kỳ • ${p.recurring.where((r) => r.active).length}',
                    () => openPage(context, const RecurringScreen())),
                const Divider(indent: 60),
                _row(context, Icons.table_view_outlined, 'Xuất Excel / CSV',
                    () => openPage(context, const ExportScreen())),
              ])),
          const SectionTitle('ỨNG DỤNG'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(context, Icons.currency_exchange,
                    'Tiền tệ báo cáo • ${p.currency}', () async {
                  final unit = await openPage<String>(context,
                      CurrencySelectionScreen(selectedCurrency: p.currency));
                  if (unit != null) p.preferences(unit: unit);
                }),
                const Divider(indent: 60),
                _row(context, Icons.price_change_outlined, 'Tỷ giá quy đổi',
                    () => openPage(context, const RatesScreen())),
                const Divider(indent: 60),
                _row(context, Icons.notifications_outlined,
                    'Thông báo nhắc nhở • ${p.remindersEnabled ? 'bật' : 'tắt'}',
                    () => openPage(context, const RemindersScreen())),
                const Divider(indent: 60),
                SwitchListTile(
                    secondary: const RoundIcon(Icons.visibility_off_outlined),
                    title: const Text('Ẩn số dư tổng quan'),
                    value: p.hideBalance,
                    onChanged: (v) => p.preferences(hidden: v)),
              ])),
          const SectionTitle('BẢO MẬT'),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _row(context, Icons.lock_outline,
                    'Khóa ứng dụng bằng PIN • ${context.watch<AppLock>().enabled ? 'bật' : 'tắt'}',
                    () => openPage(context, const SecurityScreen())),
                const Divider(indent: 60),
                if (p.signedIn) ...[
                  _row(context, Icons.lock_reset, 'Đổi mật khẩu',
                      () => openPage(context, const ChangePasswordScreen())),
                  const Divider(indent: 60),
                  ListTile(
                      leading: const RoundIcon(Icons.logout,
                          color: AppColors.accentRed),
                      title: const Text('Đăng xuất',
                          style: TextStyle(color: AppColors.accentRed)),
                      onTap: () => signOutFlow(context)),
                  const Divider(indent: 60),
                  _row(context, Icons.person_remove_outlined, 'Xóa tài khoản',
                      () => deleteAccountFlow(context)),
                ] else
                  _row(context, Icons.login, 'Đăng nhập / Đăng ký',
                      () => openPage(context, const AuthScreen(fromSettings: true))),
                const Divider(indent: 60),
                _row(context, Icons.dns_outlined, 'Máy chủ API • ${p.signedIn ? p.session!.baseUrl : p.serverUrl}',
                    p.signedIn ? () => message(context, 'Đăng xuất để đổi máy chủ.') : () => editServer(context)),
              ])),
          const SizedBox(height: 24),
          const Center(
              child: Text('Quản lý chi tiêu • Nhóm 03',
                  style: TextStyle(fontSize: 12))),
        ]));
  }

  Widget _row(BuildContext context, IconData icon, String title,
          VoidCallback onTap) =>
      ListTile(
          leading: RoundIcon(icon),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onTap);
}

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final csv = p.exportCsv();
    Future<void> share({bool csvFile = false}) async {
      try {
        await ExcelExport.share(p, csv: csvFile);
      } catch (e) {
        if (context.mounted) message(context, 'Không chia sẻ được tệp: $e');
      }
    }

    return FinancePage(
        title: 'Xuất dữ liệu',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${p.entries.length} giao dịch • ${p.wallets.length} ví • ${p.budgets.length} ngân sách',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: () => share(),
              icon: const Icon(Icons.grid_on),
              label: const Text('Xuất Excel (.xlsx) và chia sẻ')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => share(csvFile: true),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Xuất tệp CSV và chia sẻ')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: csv));
                if (context.mounted) message(context, 'Đã sao chép dữ liệu CSV.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Sao chép CSV')),
          const SizedBox(height: 12),
          const Text(
              'Tệp Excel gồm 3 trang: Giao dịch, Ví và Ngân sách. Bạn có thể gửi qua Zalo, email, lưu vào Tệp/Drive từ bảng chia sẻ.',
              style: TextStyle(fontSize: 12, height: 1.5)),
          const SectionTitle('Xem trước CSV'),
          Panel(
              child: SelectableText(csv.length > 4000 ? '${csv.substring(0, 4000)}…' : csv,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        ]));
  }
}

/// Thẻ tài khoản: email, trạng thái đồng bộ và nút đồng bộ (mục 2.4.4.6).
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final String status;
    final Color statusColor;
    if (!p.signedIn) {
      status = 'Dùng ngoại tuyến • dữ liệu chỉ lưu trên thiết bị';
      statusColor = AppColors.textSecondary;
    } else if (p.syncing) {
      status = 'Đang đồng bộ…';
      statusColor = AppColors.textSecondary;
    } else if (p.syncError != null) {
      status = p.syncError!;
      statusColor = AppColors.accentRed;
    } else if (p.pendingChanges > 0) {
      status = '${p.pendingChanges} thay đổi đang chờ đồng bộ';
      statusColor = AppColors.accentYellow;
    } else {
      status = p.lastSync == null
          ? 'Chưa đồng bộ'
          : 'Đã đồng bộ lúc ${TimeOfDay.fromDateTime(p.lastSync!).format(context)} ${dayLabel(p.lastSync!)}';
      statusColor = AppColors.primaryGreen;
    }
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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(p.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(p.signedIn ? p.session!.email : 'Hồ sơ trên thiết bị',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
            IconButton(
                tooltip: 'Đổi tên hiển thị',
                onPressed: () async {
                  final name = await editText(context, 'Tên hiển thị',
                      initial: p.displayName);
                  if (name != null) p.preferences(name: name);
                },
                icon: const Icon(Icons.edit_outlined)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Icon(
                p.signedIn
                    ? (p.syncError != null
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined)
                    : Icons.phone_android_outlined,
                size: 18,
                color: statusColor),
            const SizedBox(width: 8),
            Expanded(
                child: Text(status,
                    style: TextStyle(fontSize: 13, color: statusColor))),
            if (p.signedIn)
              p.syncing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: () => p.syncNow(),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Đồng bộ'))
            else
              TextButton(
                  onPressed: () =>
                      openPage(context, const AuthScreen(fromSettings: true)),
                  child: const Text('Đăng nhập')),
          ]),
          if (p.signedIn && !p.emailVerified)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.mark_email_unread_outlined,
                      size: 18, color: AppColors.accentOrange),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Text('Email chưa được xác thực',
                          style: TextStyle(fontSize: 13))),
                  TextButton(
                      onPressed: () => verifyEmailFlow(context),
                      child: const Text('Xác thực')),
                ])),
          if (p.signedIn && p.syncError != null && p.pendingChanges > 0)
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () async {
                      if (await confirmAction(context,
                          title: 'Bỏ thay đổi chưa đồng bộ?',
                          content:
                              'Các thay đổi chưa gửi được sẽ bị bỏ và dữ liệu trên máy được thay bằng dữ liệu của tài khoản.',
                          confirm: 'Tải lại từ máy chủ',
                          danger: true)) {
                        await p.discardLocalChanges();
                      }
                    },
                    child: const Text('Tải lại dữ liệu từ máy chủ'))),
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
          ? 'Còn $pending thay đổi chưa đồng bộ được và sẽ bị mất khi đăng xuất. Dữ liệu trên thiết bị sẽ được xóa.'
          : 'Dữ liệu đã được lưu trên tài khoản. Dữ liệu trên thiết bị này sẽ được xóa.',
      confirm: 'Đăng xuất',
      danger: pending > 0);
  if (!ok || !context.mounted) return;
  await p.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
}

Future<void> deleteAccountFlow(BuildContext context) async {
  final p = context.read<FinanceProvider>();
  final password = await editText(context, 'Nhập mật khẩu để xóa tài khoản',
      obscure: true);
  if (password == null || !context.mounted) return;
  final ok = await confirmAction(context,
      title: 'Xóa vĩnh viễn tài khoản?',
      content:
          'Toàn bộ ví, giao dịch, danh mục, đối tượng và ngân sách trên máy chủ sẽ bị xóa và không thể khôi phục.',
      confirm: 'Xóa tài khoản',
      danger: true);
  if (!ok || !context.mounted) return;
  try {
    await p.deleteAccount(password);
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false);
  } catch (e) {
    if (context.mounted) message(context, e);
  }
}

Future<void> verifyEmailFlow(BuildContext context) async {
  final p = context.read<FinanceProvider>();
  String? hint;
  try {
    final dev = await p.resendVerification();
    hint = dev == null
        ? 'Mã 6 số đã được gửi tới ${p.session?.email}.'
        : 'Máy chủ thử nghiệm chưa cấu hình email. Mã: $dev';
  } catch (e) {
    if (context.mounted) message(context, e);
    return;
  }
  if (!context.mounted) return;
  message(context, hint);
  final code = await editText(context, 'Nhập mã xác thực email');
  if (code == null || !context.mounted) return;
  try {
    await p.verifyEmail(code);
    if (context.mounted) message(context, 'Đã xác thực email.');
  } catch (e) {
    if (context.mounted) message(context, e);
  }
}
