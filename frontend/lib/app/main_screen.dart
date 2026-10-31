import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/home/presentation/home_screen.dart';
import 'package:finance_app/features/ledger/presentation/ledger_screen.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/features/goals/presentation/goals_screen.dart';
import 'package:finance_app/features/settings/presentation/others_screen.dart';
import 'package:finance_app/app/main_bottom_nav.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Quay lại ứng dụng: ghi các giao dịch định kỳ đến hạn và đồng bộ.
    final p = context.read<FinanceProvider>();
    final created = p.runRecurring();
    if (created > 0) message(context, 'Đã tự ghi $created giao dịch định kỳ đến hạn.');
    if (p.signedIn) p.syncNow();
  }
  @override
  Widget build(BuildContext context) {
    final p = context.watch<FinanceProvider>();
    return Scaffold(
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(children: [
                  if (p.storageError != null)
                    SafeArea(
                        bottom: false,
                        child: MaterialBanner(
                            content: Text(p.storageError!),
                            actions: [
                              TextButton(
                                  onPressed: p.retrySave,
                                  child: const Text('Thử lưu lại'))
                            ])),
                  Expanded(
                      child: IndexedStack(index: index, children: const [
                    HomeScreen(),
                    LedgerScreen(),
                    SizedBox.shrink(),
                    GoalsScreen(),
                    OthersScreen()
                  ])),
                ]))),
        bottomNavigationBar: MainBottomNav(
            currentIndex: index,
            onTap: (i) {
              if (i == 2) {
                openPage(context, const AddTransactionScreen());
              } else {
                setState(() => index = i);
              }
            }));
  }
}
