import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallets_screen.dart';
import 'package:finance_app/app/splash_screen.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/create_wallet_screen.dart';
import 'package:finance_app/features/settings/presentation/screens/account_screen.dart';
import 'package:finance_app/features/categories/presentation/screens/select_category_screen.dart';
import 'package:finance_app/features/categories/presentation/screens/select_person_screen.dart';
import 'package:finance_app/features/budgets/presentation/screens/budgets_screen.dart';
import 'package:finance_app/features/ai/presentation/screens/insights_screen.dart';
import 'package:finance_app/features/ai/presentation/screens/assistant_screen.dart';

void main() {
  testWidgets('Màn đăng nhập không còn chức năng bắt đầu không cần tài khoản', (tester) async {
    await tester.pumpWidget(const FinanceApp());
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.text('Bạn muốn được gọi là gì?'), findsNothing);
    expect(find.text('Bắt đầu sử dụng'), findsNothing);
    expect(find.textContaining('Không cần tài khoản'), findsNothing);
    expect(find.text('hoặc'), findsNothing);
  });
  for (final width in [320.0, 390.0, 430.0]) {
    testWidgets('Chuyển tab và lưu giao dịch trên màn rộng $width px', (tester) async {
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
      await tester.pumpAndSettle();
      for (final label in ['Sổ giao dịch', 'Trợ lý AI', 'Ngân sách', 'Tài khoản', 'Tổng quan']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('transaction-amount')), '50000');
      if (width == 430) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 336);
        await tester.pumpAndSettle();
        expect(tester.getBottomLeft(find.text('Lưu giao dịch')).dy, lessThan(596));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('Lưu giao dịch'));
      await tester.pumpAndSettle();
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
  testWidgets('Màn nhập liệu vừa màn hẹp khi phóng to chữ', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = FinanceProvider();
    p.saveEntry(MoneyEntry(
        id: 'e', kind: EntryKind.expense, amount: 50000, walletId: 'cash', categoryId: 'food', date: DateTime.now()));
    await p.flush();
    for (final page in <Widget>[
      const AddTransactionScreen(),
      const CreateWalletScreen(savings: true),
      const SelectCategoryScreen(),
      const SelectPersonScreen(),
      BudgetEditor(month: DateTime.now(), income: false),
      const InsightsScreen(),
      const AssistantScreen(),
      const AccountScreen(),
    ]) {
      await tester.pumpWidget(MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
              home: page)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scrolled ${page.runtimeType}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
  });
  testWidgets('Tài khoản không còn các chức năng đã gỡ, vẫn giữ đăng nhập', (tester) async {
    final p = FinanceProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: p, child: const MaterialApp(home: AccountScreen())));
    await tester.pumpAndSettle();
    for (final label in [
      'TRỢ LÝ AI',
      'ỨNG DỤNG',
      'Kết nối ngân hàng • VietQR',
      'Báo cáo thống kê',
      'Giao dịch định kỳ',
      'Xuất Excel / CSV',
      'Khóa ứng dụng bằng PIN',
      'Sao lưu',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
    expect(find.text('Đăng nhập / Đăng ký'), findsOneWidget);
    p.dispose();
  });
  testWidgets('Chuyển tiền vượt số dư bị chặn, không có nút vẫn lưu', (tester) async {
    final p = FinanceProvider();
    p.saveWallet(const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 500000));
    p.saveWallet(const MoneyWallet(id: 'save', name: 'Tiết kiệm', savings: true));
    final transfer = MoneyEntry(
        id: 't',
        kind: EntryKind.transfer,
        amount: 200000,
        walletId: 'cash',
        destinationId: 'save',
        date: DateTime(2026, 10, 1));
    p.saveEntry(transfer);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: p, child: MaterialApp(theme: AppTheme.lightTheme, home: AddTransactionScreen(entry: transfer))));
    await tester.enterText(find.byKey(const ValueKey('transaction-amount')), '600000');
    await tester.tap(find.text('Lưu giao dịch'));
    await tester.pumpAndSettle();
    expect(find.text('Vẫn lưu'), findsNothing);
    expect(find.text('Số dư ví Tiền mặt không đủ (còn 500.000 VND).'), findsOneWidget);
    expect(p.entries.single.amount, 200000);
    await tester.enterText(find.byKey(const ValueKey('transaction-amount')), '500000');
    await tester.tap(find.text('Lưu giao dịch'));
    await tester.pumpAndSettle();
    expect(p.entries.single.amount, 500000);
    expect(p.balance('cash'), 0);
  });

  testWidgets('Nhập nhanh và trợ lý chạy trọn luồng', (tester) async {
    final p = FinanceProvider();
    await tester.pumpWidget(FinanceApp(finance: p, returning: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-entry-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quick-entry')), 'đổ xăng 70k');
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

    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(MaterialPageRoute(builder: (_) => const AssistantScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tháng này tôi đã chi bao nhiêu?'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('70.000'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Splash vào thẳng màn chính; Drawer chuyển tab và mở trang quản lý', (tester) async {
    await tester.pumpWidget(FinanceApp(finance: FinanceProvider(), returning: true));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-drawer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    final tabs = find.descendant(of: find.byType(MainScreen), matching: find.byType(IndexedStack));
    expect(tester.widget<IndexedStack>(tabs.first).index, 1);

    await tester.dragFrom(const Offset(5, 300), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ví của tôi'));
    await tester.pumpAndSettle();
    expect(find.byType(WalletsScreen), findsOneWidget);
  });
}
