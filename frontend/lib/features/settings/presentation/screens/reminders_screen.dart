import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/services/notification_service.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  static String label(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    Future<void> enable(bool v) async {
      if (v) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted && context.mounted) {
          message(context, 'Chưa được cấp quyền thông báo. Hãy bật trong Cài đặt của hệ điều hành.');
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
                        final t =
                            await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
                        if (t != null) {
                          p.setReminders(minutes: [...p.reminderMinutes, t.hour * 60 + t.minute]);
                        }
                      }
                    : null),
          ]),
          const SizedBox(height: 16),
          const Text('Thông báo được lên lịch trên thiết bị, không cần kết nối mạng.', style: TextStyle(fontSize: 12)),
        ]));
  }
}
