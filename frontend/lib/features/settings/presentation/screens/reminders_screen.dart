import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/services/notification_service.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

// Cài đặt nhắc nhở và cảnh báo
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  static String label(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> with WidgetsBindingObserver {
  bool _granted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _readPermission();
  }

  Future<void> _readPermission() async {
    setState(() => _busy = true);
    final granted = await NotificationService.instance.hasPermission();
    if (!mounted) return;
    if (granted != _granted) {
      final finance = context.read<FinanceProvider>();
      finance.onScheduleChanged?.call(finance);
    }
    setState(() {
      _granted = granted;
      _busy = false;
    });
  }

  Future<void> _toggle(bool enabled, VoidCallback save) async {
    if (_busy) return;
    if (enabled) {
      setState(() => _busy = true);
      final granted = await NotificationService.instance.requestPermission();
      if (!mounted) return;
      setState(() {
        _granted = granted;
        _busy = false;
      });
      if (!granted) {
        message(context, 'Chưa được cấp quyền thông báo. Hãy bật trong Cài đặt của điện thoại.');
        return;
      }
    }
    save();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final daily = _granted && p.remindersEnabled;

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
                  value: daily,
                  onChanged: _busy ? null : (v) => _toggle(v, () => p.setReminders(enabled: v)),
                ),
                const Divider(indent: 60),
                SwitchListTile(
                  tileColor: Colors.transparent,
                  secondary: const RoundIcon(Icons.event_available),
                  title: const Text('Nhắc hạn trả/thu nợ'),
                  subtitle: const Text('Lúc 9:00 trước hạn 1 ngày và đúng ngày đến hạn'),
                  value: _granted && p.debtReminders,
                  onChanged: _busy ? null : (v) => _toggle(v, () => p.setReminders(debts: v)),
                ),
                const Divider(indent: 60),
                SwitchListTile(
                  tileColor: Colors.transparent,
                  secondary: const RoundIcon(Icons.notifications_outlined),
                  title: const Text('Cảnh báo vượt ngân sách'),
                  subtitle: const Text('Báo khi số tiền đã chi vượt hạn mức'),
                  value: _granted && p.budgetAlertsEnabled,
                  onChanged: _busy ? null : (v) => _toggle(v, () => p.setReminders(budgetAlerts: v)),
                ),
              ])),
          const SectionTitle('Giờ nhắc'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in {9 * 60, 15 * 60, 20 * 60, ...p.reminderMinutes})
              FilterChip(
                  label: Text(RemindersScreen.label(m)),
                  selected: p.reminderMinutes.contains(m),
                  onSelected: daily
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
                onPressed: daily
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
