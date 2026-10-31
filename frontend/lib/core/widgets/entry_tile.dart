import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class EntryTile extends StatelessWidget {
  const EntryTile(this.entry, {super.key});
  final MoneyEntry entry;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final c = p.category(entry.categoryId);
    final w = p.wallet(entry.walletId);
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: RoundIcon(c?.icon ??
              (entry.kind.isDebt
                  ? Icons.handshake_outlined
                  : Icons.swap_horiz)),
          title: Text(c?.name ?? entry.kind.label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${w.name}${entry.destinationId == null ? '' : ' → ${p.wallet(entry.destinationId!).name}'}\n${dayLabel(entry.date)}${entry.personId == null ? '' : ' • ${p.personName(entry.personId)}'}${entry.note.isEmpty ? '' : '\n${entry.note}'}'),
          isThreeLine: true,
          trailing: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .30),
              child: Text(
                  '${entry.kind == EntryKind.transfer ? '' : entry.kind.sign > 0 ? '+' : '−'}${money(entry.amount, w.currency)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: entry.kind == EntryKind.transfer
                          ? AppColors.textSecondary
                          : entry.kind.sign > 0
                              ? AppColors.primaryGreen
                              : AppColors.accentRed))),
          onTap: () => openPage(context, AddTransactionScreen(entry: entry)),
        ));
  }
}
