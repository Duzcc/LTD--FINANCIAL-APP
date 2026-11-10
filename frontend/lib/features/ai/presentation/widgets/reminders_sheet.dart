import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';

String reminderWhen(DateTime d) => DateFormat('HH:mm, dd/MM/yyyy').format(d);

Future<void> showReminders(BuildContext context) => showModalBottomSheet<void>(
    context: context, useSafeArea: true, isScrollControlled: true, builder: (_) => const RemindersSheet());

class RemindersSheet extends StatelessWidget {
  const RemindersSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final now = DateTime.now();
    final list = p.reminders.where((r) => !r.expired(now)).toList()
      ..sort((a, b) => a.nextAfter(now).compareTo(b.nextAfter(now)));
    return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(0, 8, 0, 16), children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('Nhắc nhở chi tiêu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          if (list.isEmpty)
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text('Chưa có nhắc nhở nào. Nhắn "nhắc tôi đóng tiền điện ngày 15 hàng tháng" để tạo.',
                    style: TextStyle(height: 1.4))),
          for (final r in list)
            ListTile(
                leading: const RoundIcon(Icons.notifications_active_outlined),
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${r.repeat.label} • lần tới ${reminderWhen(r.nextAfter(now))}'),
                trailing: IconButton(
                    tooltip: 'Xóa nhắc nhở',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => p.deleteReminder(r.id))),
        ]));
  }
}
