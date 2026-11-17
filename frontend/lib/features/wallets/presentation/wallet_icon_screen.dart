import 'package:flutter/material.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/entity_icons.dart';

/// Trả về chỉ số biểu tượng đã chọn qua Navigator.pop.
class WalletIconScreen extends StatelessWidget {
  const WalletIconScreen({super.key, required this.selected});
  final int selected;

  @override
  Widget build(BuildContext context) => FinancePage(
      title: 'Chọn biểu tượng',
      child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12),
          itemCount: walletIcons.length,
          itemBuilder: (context, i) => _IconChoice(
              key: ValueKey('wallet-icon-$i'),
              icon: walletIcons[i],
              selected: i == selected,
              onTap: () => Navigator.pop(context, i))));
}

class _IconChoice extends StatelessWidget {
  const _IconChoice(
      {super.key, required this.icon, required this.selected, required this.onTap});
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: selected ? AppColors.primaryGreenSurface : AppColors.cardWhite,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected ? AppColors.primaryGreen : AppColors.divider,
              width: selected ? 2 : 1)),
      child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Icon(icon,
              size: 30,
              color: selected ? AppColors.primaryGreen : AppColors.textSecondary)));
}
