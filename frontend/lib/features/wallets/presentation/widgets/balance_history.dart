import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/charts.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';

class BalanceHistory extends StatelessWidget {
  const BalanceHistory({super.key, required this.walletId, required this.color, this.months = 6});
  final String walletId;
  final Color color;
  final int months;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final now = DateTime.now();
    final starts = [for (var i = months - 1; i >= 0; i--) DateTime(now.year, now.month - i)];
    final values = [
      for (final m in starts) p.balanceAt(walletId, DateTime(m.year, m.month + 1)).clamp(0, double.infinity).toDouble()
    ];
    return Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Số dư cuối mỗi tháng', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      SizedBox(
          height: 160,
          child: CompareBarChart(labels: [for (final m in starts) 'T${m.month}'], values: values, colors: [color])),
    ]));
  }
}
