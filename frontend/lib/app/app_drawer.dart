import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/widgets/brand_logo.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/categories/presentation/screens/select_category_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallets_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  static const _tabs = [
    (0, Icon(Icons.home_rounded), 'Tổng quan'),
    (1, Icon(Icons.receipt_long_rounded), 'Sổ giao dịch'),
    (3, BrandLogo.ai(size: 24), 'Trợ lý AI'),
    (4, Icon(Icons.track_changes_rounded), 'Ngân sách'),
    (5, Icon(Icons.person_outline_rounded), 'Tài khoản'),
  ];

  void _open(BuildContext context, Widget page) {
    Navigator.pop(context);
    openPage(context, page);
  }

  @override
  Widget build(BuildContext context) {
    final name = context.select<FinanceProvider, String>((p) => p.displayName);
    final email = context.select<FinanceProvider, String?>((p) => p.session?.email);
    return Drawer(
        backgroundColor: AppColors.backgroundBeige,
        child: ListTileTheme(
            tileColor: Colors.transparent,
            shape: const RoundedRectangleBorder(),
            child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
              DrawerHeader(
                  decoration: const BoxDecoration(color: AppColors.cardBeige),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const BrandLogo.app(size: 56),
                    const Spacer(),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    Text(email ?? 'Chưa đăng nhập',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ])),
              for (final (index, leading, label) in _tabs)
                ListTile(
                    key: ValueKey('drawer-tab-$index'),
                    leading: leading,
                    title: Text(label),
                    selected: selected == index,
                    selectedColor: AppColors.primaryGreen,
                    selectedTileColor: AppColors.primaryGreenSurface,
                    onTap: () => onSelect(index)),
              const Divider(),
              ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Ví của tôi'),
                  onTap: () => _open(context, const WalletsScreen())),
              ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Danh mục'),
                  onTap: () => _open(context, const SelectCategoryScreen(manage: true))),
            ])));
  }
}
