import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/wallets/presentation/wallet_detail_screen.dart';
import 'package:finance_app/features/statistics/presentation/statistics_screen.dart';
import 'package:finance_app/features/ledger/presentation/ledger_screen.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/core/security/app_lock.dart';

// Opt-in visual inspection artifacts; no seed data is inserted into the real app.
void main() {
  testWidgets('Capture phone previews', (tester) async {
    const fontDir = String.fromEnvironment('PREVIEW_FONT_DIR');
    if (fontDir.isNotEmpty) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto')
          ..addFont(File('$fontDir/Roboto-Regular.ttf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)));
        await loader.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(File('$fontDir/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then((v) => ByteData.sublistView(v)));
        await icons.load();
      });
    }
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final p = FinanceProvider();
    final now = DateTime.now();
    p.preferences(name: 'Đức');
    p.saveWallet(
        const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 2500000));
    p.saveWallet(const MoneyWallet(
        id: 'saving',
        name: 'Mua MacBook',
        opening: 3000000,
        savings: true,
        target: 25000000));
    p.saveEntry(MoneyEntry(
        id: 'salary',
        kind: EntryKind.income,
        amount: 12000000,
        walletId: 'cash',
        categoryId: 'salary',
        date: now));
    p.saveEntry(MoneyEntry(
        id: 'food',
        kind: EntryKind.expense,
        amount: 85000,
        walletId: 'cash',
        categoryId: 'food',
        date: now,
        note: 'Bữa trưa cùng bạn bè'));
    p.saveEntry(MoneyEntry(
        id: 'home',
        kind: EntryKind.expense,
        amount: 3200000,
        walletId: 'cash',
        categoryId: 'house',
        date: now));
    p.saveBudget(MoneyBudget(
        id: 'food', categoryId: 'food', month: now, amount: 2000000));
    p.saveBudget(MoneyBudget(
        id: 'home', categoryId: 'house', month: now, amount: 4000000));
    p.saveBudget(MoneyBudget(
        id: 'all', categoryId: null, month: now, amount: 6000000));
    p.savePerson(const MoneyPerson('an', 'Anh Tuấn', 'Bạn bè & Đồng nghiệp'));
    p.saveEntry(MoneyEntry(
        id: 'lend',
        kind: EntryKind.lend,
        amount: 1500000,
        walletId: 'cash',
        personId: 'an',
        date: now.subtract(const Duration(days: 20)),
        dueDate: now.add(const Duration(days: 3))));
    p.saveEntry(MoneyEntry(
        id: 'collect',
        kind: EntryKind.collect,
        amount: 500000,
        walletId: 'cash',
        personId: 'an',
        date: now));
    p.saveEntry(MoneyEntry(
        id: 'last',
        kind: EntryKind.expense,
        amount: 2600000,
        walletId: 'cash',
        categoryId: 'food',
        date: DateTime(now.year, now.month - 1, 12)));
    await p.flush();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/previews').create(recursive: true);
        await File('build/previews/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    final lock = AppLock();
    Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: p),
          ChangeNotifierProvider.value(value: lock),
        ],
        child: MaterialApp(
            theme: AppTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            home:
                RepaintBoundary(key: const ValueKey('capture'), child: child)));
    await tester.pumpWidget(wrap(const AuthScreen()));
    await capture('auth');
    await tester.pumpWidget(wrap(const MainScreen()));
    await capture('overview');
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await capture('overview_2');
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.drag(find.byType(ListView).first, const Offset(0, 700));
    await capture('overview_trend');
    await tester.tap(find.text('Sổ nợ'));
    await capture('debt');
    await tester.tap(find.text('Ví').first);
    await capture('wallets');
    await tester.tap(find.text('Sổ giao dịch').last);
    await capture('ledger');
    await tester.tap(find.text('Ngân sách').last);
    await capture('budgets');
    await tester.tap(find.text('Tài khoản').last);
    await capture('account');
    await tester.pumpWidget(wrap(const AddTransactionScreen()));
    await capture('transaction');
    await tester.pumpWidget(wrap(const CreateWalletScreen(savings: true)));
    await capture('wallet');
    await tester.pumpWidget(wrap(const WalletDetailScreen(walletId: 'saving')));
    await capture('wallet_detail');
    await tester.pumpWidget(wrap(const StatisticsScreen()));
    await capture('statistics');
    await tester.pumpWidget(wrap(const LedgerScreen()));
    await capture('ledger_page');
    await tester.pumpWidget(wrap(const InsightsScreen()));
    await capture('insights');
    await tester.pumpWidget(wrap(const AssistantScreen()));
    await tester.tap(find.text('Dự báo chi tiêu cuối tháng'));
    await tester.pumpAndSettle();
    await capture('assistant');
    await tester.pumpWidget(wrap(const RecurringEditor()));
    await capture('recurring_editor');

    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
  }, skip: !const bool.fromEnvironment('CAPTURE_PREVIEWS'));
}
