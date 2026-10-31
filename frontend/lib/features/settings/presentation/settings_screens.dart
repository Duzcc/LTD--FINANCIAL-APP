import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/core/notifications/notification_service.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/security/presentation/lock_screen.dart';
import 'package:finance_app/features/wallets/presentation/currency_selection_screen.dart';

/// Tỷ giá dùng để quy đổi tổng tài sản nhiều tiền tệ (người dùng tự cập nhật).
class RatesScreen extends StatelessWidget {
  const RatesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return FinancePage(
        title: 'Tỷ giá quy đổi',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Tỷ giá được dùng để xem tổng tài sản quy đổi khi bạn có ví ở nhiều tiền tệ. Số liệu thu chi vẫn được thống kê riêng theo từng tiền tệ.',
              style: TextStyle(height: 1.5)),
          const SizedBox(height: 16),
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final unit in CurrencySelectionScreen.units.keys.where((u) => u != 'VND'))
                  ListTile(
                      tileColor: Colors.transparent,
                      title: Text(CurrencySelectionScreen.units[unit]!),
                      subtitle: Text('1 $unit = ${money(p.rates[unit] ?? 0)}'),
                      trailing: const Icon(Icons.edit_outlined, size: 18),
                      onTap: () async {
                        final text = await editText(context, 'Giá 1 $unit (VND)',
                            initial: formatAmountInput(p.rates[unit] ?? 0), numeric: true);
                        if (text == null || !context.mounted) return;
                        try {
                          p.setRate(unit, parseAmount(text) ?? 0);
                        } catch (e) {
                          message(context, e);
                        }
                      }),
              ])),
          const SizedBox(height: 12),
          TextButton.icon(
              onPressed: () {
                FinanceProvider.defaultRates.forEach((k, v) {
                  if (k != 'VND') p.setRate(k, v);
                });
              },
              icon: const Icon(Icons.restore),
              label: const Text('Khôi phục tỷ giá mặc định')),
          if (p.hasManyCurrencies) ...[
            const SectionTitle('Tổng tài sản quy đổi'),
            Panel(
                child: Text(money(p.convertedTotal(p.currency), p.currency),
                    style: Theme.of(context).textTheme.headlineSmall)),
          ],
        ]));
  }
}

/// Nhắc ghi chép hằng ngày và nhắc hạn nợ bằng thông báo hệ điều hành.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static String label(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    Future<void> enable(bool v) async {
      if (v) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted && context.mounted) {
          message(context,
              'Chưa được cấp quyền thông báo. Hãy bật trong Cài đặt của hệ điều hành.');
        }
      }
      p.setReminders(enabled: v);
    }

    return FinancePage(
        title: 'Thông báo nhắc nhở',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                    tileColor: Colors.transparent,
                    secondary: const RoundIcon(Icons.notifications_active_outlined),
                    title: const Text('Nhắc ghi chép hằng ngày'),
                    subtitle: const Text('Hình thành thói quen ghi lại thu chi'),
                    value: p.remindersEnabled,
                    onChanged: enable),
                const Divider(indent: 60),
                SwitchListTile(
                    tileColor: Colors.transparent,
                    secondary: const RoundIcon(Icons.event_available),
                    title: const Text('Nhắc hạn trả/thu nợ'),
                    subtitle: const Text('Lúc 9:00 trước hạn 1 ngày và đúng ngày đến hạn'),
                    value: p.debtReminders,
                    onChanged: (v) => p.setReminders(debts: v)),
              ])),
          const SectionTitle('Giờ nhắc'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in {9 * 60, 15 * 60, 20 * 60, ...p.reminderMinutes})
              FilterChip(
                  label: Text(label(m)),
                  selected: p.reminderMinutes.contains(m),
                  onSelected: p.remindersEnabled
                      ? (v) {
                          final next = [...p.reminderMinutes];
                          if (v) {
                            next.add(m);
                          } else if (next.length > 1) {
                            next.remove(m);
                          }
                          p.setReminders(minutes: next);
                        }
                      : null),
            ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Giờ khác'),
                onPressed: p.remindersEnabled
                    ? () async {
                        final t = await showTimePicker(
                            context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
                        if (t != null) {
                          p.setReminders(minutes: [...p.reminderMinutes, t.hour * 60 + t.minute]);
                        }
                      }
                    : null),
          ]),
          const SizedBox(height: 16),
          const Text(
              'Thông báo được lên lịch trên thiết bị, không cần kết nối mạng.',
              style: TextStyle(fontSize: 12)),
        ]));
  }
}

/// Khóa ứng dụng bằng mã PIN.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLock>();
    return FinancePage(
        title: 'Khóa ứng dụng',
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                    tileColor: Colors.transparent,
                    secondary: const RoundIcon(Icons.lock_outline),
                    title: const Text('Khóa bằng mã PIN'),
                    subtitle: const Text('Yêu cầu mã khi mở ứng dụng hoặc quay lại sau 30 giây'),
                    value: lock.enabled,
                    onChanged: (v) async {
                      if (v) {
                        await openPage(context, const PinSetupScreen());
                      } else {
                        final ok = await openPage<bool>(
                            context, const PinSetupScreen(verifyOnly: true));
                        if (ok == true) await lock.disable();
                      }
                    }),
                if (lock.enabled) ...[
                  const Divider(indent: 60),
                  ListTile(
                      tileColor: Colors.transparent,
                      leading: const RoundIcon(Icons.password),
                      title: const Text('Đổi mã PIN'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openPage(context, const PinSetupScreen())),
                ],
              ])),
          const SizedBox(height: 12),
          const Text(
              'Mã PIN chỉ được lưu trên thiết bị dưới dạng băm SHA-256 có muối. Nếu quên mã, hãy cài lại ứng dụng và đăng nhập để tải dữ liệu từ tài khoản.',
              style: TextStyle(fontSize: 12, height: 1.5)),
        ]));
  }
}
