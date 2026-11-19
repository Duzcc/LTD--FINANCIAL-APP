import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/screens/currency_selection_screen.dart';

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
                        attempt(context, () {
                          p.setRate(unit, parseAmount(text) ?? 0);
                        });
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
