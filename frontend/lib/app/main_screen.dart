import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/home/presentation/screens/home_screen.dart';
import 'package:finance_app/features/ledger/presentation/screens/ledger_screen.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:finance_app/features/budgets/presentation/screens/budgets_screen.dart';
import 'package:finance_app/features/ai/presentation/screens/assistant_screen.dart';
import 'package:finance_app/features/settings/presentation/screens/account_screen.dart';
import 'package:finance_app/app/app_drawer.dart';
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
    final p = context.read<FinanceProvider>();
    final created = p.runRecurring();
    if (created > 0) message(context, 'Đã tự ghi $created giao dịch định kỳ đến hạn.');
    if (p.signedIn) p.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final storageError = context.select<FinanceProvider, String?>((p) => p.storageError);
    return Scaffold(
        drawer: AppDrawer(
            selected: index,
            onSelect: (i) {
              Navigator.pop(context);
              setState(() => index = i);
            }),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(children: [
                  if (storageError != null)
                    SafeArea(
                        bottom: false,
                        child: MaterialBanner(content: Text(storageError), actions: [
                          TextButton(
                              onPressed: context.read<FinanceProvider>().retrySave, child: const Text('Thử lưu lại'))
                        ])),
                  Expanded(
                      child: IndexedStack(index: index, children: const [
                    HomeScreen(),
                    LedgerScreen(),
                    SizedBox.shrink(),
                    AssistantScreen(),
                    BudgetsScreen(),
                    AccountScreen()
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
