import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_person_screen.dart';
import 'package:finance_app/features/goals/presentation/goals_screen.dart';
import 'package:finance_app/features/statistics/presentation/statistics_screen.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/features/settings/presentation/settings_screens.dart';
import 'package:finance_app/features/settings/presentation/others_screen.dart';
import 'package:finance_app/core/security/app_lock.dart';

void main() {
  testWidgets('Local onboarding opens the connected app', (tester) async {
    await tester.pumpWidget(const FinanceApp());
    expect(find.text('Đăng nhập'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Bắt đầu sử dụng'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Bắt đầu sử dụng'));
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('Phone navigation and transaction save at $width px',
        (tester) async {
      tester.view.physicalSize = Size(width, width == 430 ? 932 : 740);
      if (width == 430) {
        tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      final p = FinanceProvider();
      await tester.pumpWidget(FinanceApp(finance: p, returning: true));
      for (final label in [
        'Sổ giao dịch',
        'Ngân sách',
        'Tài khoản',
        'Tổng quan'
      ]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('transaction-amount')), '50000');
      if (width == 430) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 336);
        await tester.pumpAndSettle();
        expect(
            tester.getBottomLeft(find.text('Lưu giao dịch')).dy, lessThan(596));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Lưu giao dịch'));
      await tester.pumpAndSettle();
      // Ví đang có 0 ₫ nên ứng dụng cảnh báo chi vượt số dư trước khi lưu.
      expect(find.text('Số tiền vượt số dư ví'), findsOneWidget);
      await tester.tap(find.text('Vẫn lưu'));
      await tester.pumpAndSettle();
      expect(p.entries.length, 1);
      expect(p.entries.single.amount, 50000);
      expect(p.balance('cash'), -50000);
      expect(p.total(DateTime.now(), income: false), 50000);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Editors and reports fit narrow phones with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = FinanceProvider();
    p.saveEntry(MoneyEntry(
        id: 'e',
        kind: EntryKind.expense,
        amount: 50000,
        walletId: 'cash',
        categoryId: 'food',
        date: DateTime.now()));
    await p.flush();
    for (final page in <Widget>[
      const AddTransactionScreen(),
      const CreateWalletScreen(savings: true),
      const SelectCategoryScreen(),
      const SelectPersonScreen(),
      BudgetEditor(month: DateTime.now(), income: false),
      const StatisticsScreen(),
      const InsightsScreen(),
      const AssistantScreen(),
      const RecurringScreen(),
      const RecurringEditor(),
      const SecurityScreen(),
      const RatesScreen(),
      const RemindersScreen(),
      const ExportScreen(),
      const OthersScreen(),
    ]) {
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: p),
            ChangeNotifierProvider(create: (_) => AppLock()),
          ],
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!),
              home: page)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'scrolled ${page.runtimeType}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
  });
  testWidgets('Quick entry and assistant flows work end to end', (tester) async {
    final p = FinanceProvider();
    await tester.pumpWidget(FinanceApp(finance: p, returning: true));
    await tester.tap(find.byKey(const ValueKey('quick-entry-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('quick-entry')), 'đổ xăng 70k');
    await tester.pumpAndSettle();
    expect(find.text('Đi lại'), findsWidgets);
    await tester.ensureVisible(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTransactionScreen), findsOneWidget);
    expect(find.text('70.000'), findsOneWidget);
    await tester.tap(find.text('Lưu giao dịch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vẫn lưu'));
    await tester.pumpAndSettle();
    expect(p.entries.single.categoryId, 'transport');
    expect(p.entries.single.amount, 70000);

    // Mở trợ lý trong cùng ứng dụng (FinanceApp sở hữu và giải phóng provider).
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute(builder: (_) => const AssistantScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tháng này tôi đã chi bao nhiêu?'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('70.000'), findsWidgets);
    expect(find.text('AI trên thiết bị'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
