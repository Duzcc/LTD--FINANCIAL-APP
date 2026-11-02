import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/entry_tile.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/wallets/presentation/wallets_screen.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/features/banking/presentation/receive_qr_screen.dart';

/// Thông tin và các giao dịch của một ví; sửa hoặc xóa ví.
class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({super.key, required this.walletId});
  final String walletId;
  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  DateTime month = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final w = p.findWallet(widget.walletId);
    if (w == null) {
      return const FinancePage(
          title: 'Ví',
          child: EmptyView(
              title: 'Ví đã bị xóa', subtitle: 'Quay lại để tiếp tục.'));
    }
    final balance = p.balance(w.id);
    final entries = p.inMonth(month, walletId: w.id);
    var inflow = 0.0, outflow = 0.0;
    for (final e in entries) {
      final incoming = e.kind == EntryKind.transfer
          ? e.destinationId == w.id
          : e.kind.sign > 0;
      if (incoming) {
        inflow += e.amount;
      } else {
        outflow += e.amount;
      }
    }
    return FinancePage(
        title: w.name,
        actions: [
          IconButton(
              tooltip: 'Chỉnh sửa ví',
              onPressed: () async {
                final result =
                    await openPage<String>(context, CreateWalletScreen(wallet: w));
                if (result == 'deleted' && context.mounted) {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.edit_outlined)),
        ],
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
              color: w.savings ? const Color(0xFFF1E4D6) : const Color(0xFFE6EEE8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      RoundIcon(w.icon),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(
                              '${w.savings ? 'Ví tiết kiệm' : 'Ví cơ bản'} • ${w.currency}')),
                      if (w.excluded) const Chip(label: Text('Không tính tổng')),
                    ]),
                    const SizedBox(height: 14),
                    const Text('Số dư hiện tại', style: TextStyle(fontSize: 12)),
                    Text(secret(p.hideBalance, balance, w.currency),
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: balance < 0
                                ? AppColors.accentRed
                                : AppColors.textPrimary)),
                    Text('Số dư ban đầu ${money(w.opening, w.currency)}',
                        style: const TextStyle(fontSize: 12)),
                    if (w.savings) ...[
                      const SizedBox(height: 14),
                      if (w.target > 0)
                        SavingsProgress(wallet: w, balance: balance),
                      const SizedBox(height: 6),
                      Text(
                          [
                            if (w.startDate != null)
                              'Bắt đầu ${dayLabel(w.startDate!)}',
                            if (w.deadline != null)
                              'Kết thúc ${dayLabel(w.deadline!)}',
                          ].join(' • '),
                          style: const TextStyle(fontSize: 12)),
                      if (w.target > balance && w.deadline != null)
                        Builder(builder: (_) {
                          final days = DateUtilsDate.day(w.deadline!)
                              .difference(DateUtilsDate.day(DateTime.now()))
                              .inDays;
                          if (days <= 0) {
                            return const Text('Đã đến hạn mục tiêu.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.accentRed));
                          }
                          final months = math.max(1, (days / 30).ceil());
                          return Text(
                              'Cần để dành thêm ${money(w.target - balance, w.currency)} • khoảng ${money((w.target - balance) / months, w.currency)}/tháng',
                              style: const TextStyle(fontSize: 12));
                        }),
                    ],
                  ])),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: () => openPage(
                        context, AddTransactionScreen(initialWalletId: w.id)),
                    icon: const Icon(Icons.add),
                    label: const Text('Giao dịch'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => openPage(
                        context,
                        AddTransactionScreen(
                            initialKind: EntryKind.transfer,
                            initialWalletId: w.id)),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Chuyển tiền'))),
          ]),
          if (w.hasBank) ...[
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    key: const ValueKey('receive-qr'),
                    onPressed: () =>
                        openPage(context, ReceiveQrScreen(walletId: w.id)),
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('Nhận tiền bằng VietQR'))),
          ],
          if (w.savings) ...[
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                    onPressed: () {
                      final source = p.wallets
                          .where((x) => !x.savings && x.currency == w.currency)
                          .firstOrNull;
                      final days = w.deadline == null
                          ? 0
                          : DateUtilsDate.day(w.deadline!)
                              .difference(DateUtilsDate.day(DateTime.now()))
                              .inDays;
                      final months = math.max(1, (days / 30).ceil());
                      openPage(
                          context,
                          RecurringEditor(
                              initialKind: EntryKind.transfer,
                              initialWalletId: source?.id,
                              initialDestinationId: w.id,
                              initialAmount: w.target > balance && days > 0
                                  ? ((w.target - balance) / months).ceilToDouble()
                                  : null,
                              initialNote: 'Nạp ${w.name}'));
                    },
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Tự động nạp tiết kiệm hằng tháng'))),
          ],
          const SizedBox(height: 12),
          MonthPicker(
              value: month, onChanged: (v) => setState(() => month = v)),
          Panel(
              child: Row(children: [
            Expanded(
                child: Text('Tiền vào\n${money(inflow, w.currency)}',
                    style: const TextStyle(color: AppColors.primaryGreen))),
            Expanded(
                child: Text('Tiền ra\n${money(outflow, w.currency)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.accentRed))),
          ])),
          const SizedBox(height: 12),
          for (final e in entries) EntryTile(e),
          if (entries.isEmpty)
            const EmptyView(
                title: 'Chưa có giao dịch',
                subtitle: 'Ví chưa phát sinh giao dịch trong tháng này.'),
        ]));
  }
}
