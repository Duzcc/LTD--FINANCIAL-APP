import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/wallets/presentation/wallet_detail_screen.dart';

class WalletsScreen extends StatelessWidget {
  const WalletsScreen({super.key});
  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Ví của tôi',
      actions: [
        IconButton(
            tooltip: 'Thêm ví',
            onPressed: () => openPage(context, const CreateWalletScreen()),
            icon: const Icon(Icons.add))
      ],
      child: const WalletList());
}

/// Danh sách ví (tab Ví ở Tổng quan và màn hình Cài đặt ví).
class WalletList extends StatefulWidget {
  const WalletList({super.key});
  @override
  State<WalletList> createState() => _WalletListState();
}

class _WalletListState extends State<WalletList> {
  bool spendableOnly = false;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final units = {p.currency, ...p.wallets.map((w) => w.currency)};
    return ListView(padding: const EdgeInsets.all(16), children: [
      Panel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('Ví của tôi',
                  style: TextStyle(fontWeight: FontWeight.w700))),
          Chip(
              label: Text('${p.wallets.length} ví'),
              visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 6),
        Text(spendableOnly ? 'Tài sản có thể dùng ngay' : 'Tổng tài sản',
            style: const TextStyle(fontSize: 12)),
        for (final unit in units)
          if (p.wallets.any((w) => w.currency == unit))
            Text(
                secret(p.hideBalance,
                    p.totalBalance(unit, spendableOnly: spendableOnly), unit),
                style: Theme.of(context).textTheme.headlineSmall),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            tileColor: Colors.transparent,
            title: const Text('Chỉ tính tài sản có thể dùng ngay'),
            subtitle: const Text('Bỏ qua ví tiết kiệm khi tính tổng'),
            value: spendableOnly,
            onChanged: (v) => setState(() => spendableOnly = v)),
      ])),
      for (final savings in [false, true]) ...[
        SectionTitle(savings ? 'Ví tiết kiệm' : 'Ví cơ bản'),
        for (final w in p.wallets.where((w) => w.savings == savings))
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WalletCard(wallet: w)),
        if (!p.wallets.any((w) => w.savings == savings))
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(savings
                  ? 'Chưa có ví tiết kiệm. Tạo ví để dành tiền cho một mục tiêu cụ thể.'
                  : 'Chưa có ví cơ bản.')),
      ],
      const SizedBox(height: 4),
      FilledButton.icon(
          onPressed: () => openPage(context, const CreateWalletScreen()),
          icon: const Icon(Icons.add),
          label: const Text('Thêm ví')),
    ]);
  }
}

class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.wallet});
  final MoneyWallet wallet;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    final w = wallet;
    final balance = p.balance(w.id);
    return Panel(
        padding: EdgeInsets.zero,
        child: InkWell(
            onTap: () => openPage(context, WalletDetailScreen(walletId: w.id)),
            child: Column(children: [
              ListTile(
                  tileColor: Colors.transparent,
                  leading: Badge(
                      isLabelVisible: !w.excluded,
                      backgroundColor: AppColors.primaryGreen,
                      label: const Icon(Icons.check, size: 8, color: Colors.white),
                      child: RoundIcon(w.icon,
                          color: w.savings
                              ? const Color(0xFFBC956D)
                              : const Color(0xFF7C9583))),
                  title: Text(w.name),
                  subtitle: Text(
                      '${w.savings ? 'Tiết kiệm' : 'Cơ bản'} • ${w.currency}${w.excluded ? ' • không tính vào tổng' : ''}'),
                  trailing: Text(secret(p.hideBalance, balance, w.currency),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: balance < 0
                              ? AppColors.accentRed
                              : AppColors.textPrimary))),
              if (w.savings && w.target > 0)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SavingsProgress(wallet: w, balance: balance)),
            ])));
  }
}

class SavingsProgress extends StatelessWidget {
  const SavingsProgress({super.key, required this.wallet, required this.balance});
  final MoneyWallet wallet;
  final double balance;
  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final ratio = w.target == 0 ? 0.0 : (balance / w.target);
    final today = DateUtilsDate.day(DateTime.now());
    final daysLeft = w.deadline == null
        ? null
        : DateUtilsDate.day(w.deadline!).difference(today).inDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LinearProgressIndicator(
          value: ratio.clamp(0, 1),
          minHeight: 6,
          color: ratio >= 1 ? AppColors.primaryGreen : const Color(0xFFBC956D),
          backgroundColor: AppColors.backgroundBeige,
          borderRadius: BorderRadius.circular(8)),
      const SizedBox(height: 8),
      Text(
          '${(ratio * 100).clamp(0, 999).toStringAsFixed(0)}% mục tiêu ${money(w.target, w.currency)}'
          '${daysLeft == null ? '' : daysLeft < 0 ? ' • đã quá hạn' : ' • còn $daysLeft ngày'}',
          style: const TextStyle(fontSize: 12)),
    ]);
  }
}
