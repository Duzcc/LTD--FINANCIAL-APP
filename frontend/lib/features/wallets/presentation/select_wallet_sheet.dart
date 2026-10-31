import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';

class SelectWalletSheet extends StatelessWidget {
  const SelectWalletSheet(
      {super.key, this.selectedWallet, this.excludeId, this.currency});
  final String? selectedWallet, excludeId, currency;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final wallets = p.wallets
        .where((w) =>
            w.id != excludeId && (currency == null || w.currency == currency))
        .toList();
    return SafeArea(
        child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
          const SectionTitle('Chọn ví'),
          for (final w in wallets)
            ListTile(
                leading: RoundIcon(w.icon),
                title: Text(w.name),
                subtitle: Text(money(p.balance(w.id), w.currency)),
                trailing: w.id == selectedWallet
                    ? const Icon(Icons.check, color: AppColors.primaryGreen)
                    : null,
                onTap: () => Navigator.pop(context, w.id)),
          if (wallets.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Chưa có ví phù hợp. Hãy thêm ví cùng tiền tệ để chuyển tiền.')),
          TextButton.icon(
              onPressed: () => openPage(context, const CreateWalletScreen()),
              icon: const Icon(Icons.add),
              label: const Text('Thêm ví')),
        ]));
  }
}
