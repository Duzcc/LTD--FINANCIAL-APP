import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/ledger/presentation/screens/ledger_screen.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';

FinanceProvider _seedProvider() {
  final p = FinanceProvider();
  p.saveWallet(const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 1000000));
  p.saveWallet(const MoneyWallet(id: 'bank', name: 'Ngân hàng ACB', opening: 5000000));
  p.savePerson(const MoneyPerson('minh', 'Minh', 'Bạn bè'));
  p.savePerson(const MoneyPerson('lan', 'Lan', 'Bạn bè'));

  final now = DateTime.now();
  final thisMonth = DateTime(now.year, now.month, 10, 9);
  final prevMonth = DateTime(now.year, now.month - 1, 15, 10);

  p.saveEntry(MoneyEntry(
      id: 'e_coffee',
      kind: EntryKind.expense,
      amount: 70000,
      walletId: 'cash',
      categoryId: 'food',
      date: thisMonth,
      note: 'Cà phê sáng'));
  p.saveEntry(MoneyEntry(
      id: 'e_gas',
      kind: EntryKind.expense,
      amount: 120000,
      walletId: 'bank',
      categoryId: 'transport',
      date: thisMonth.add(const Duration(hours: 2)),
      note: 'Đổ xăng xe máy'));
  p.saveEntry(MoneyEntry(
      id: 'e_salary',
      kind: EntryKind.income,
      amount: 2000000,
      walletId: 'bank',
      categoryId: 'salary',
      date: thisMonth.add(const Duration(hours: 3)),
      note: 'Lương tháng này'));
  p.saveEntry(MoneyEntry(
      id: 'e_transfer',
      kind: EntryKind.transfer,
      amount: 300000,
      walletId: 'bank',
      destinationId: 'cash',
      date: thisMonth.add(const Duration(hours: 4)),
      note: 'Rút tiền mặt'));
  p.saveEntry(MoneyEntry(
      id: 'e_lend',
      kind: EntryKind.lend,
      amount: 500000,
      walletId: 'cash',
      personId: 'minh',
      date: thisMonth.add(const Duration(hours: 5)),
      note: 'Cho bạn mượn'));
  p.saveEntry(MoneyEntry(
      id: 'e_excluded',
      kind: EntryKind.expense,
      amount: 50000,
      walletId: 'cash',
      categoryId: 'food',
      date: thisMonth.add(const Duration(hours: 6)),
      note: 'Điều chỉnh số dư',
      excluded: true));
  p.saveEntry(MoneyEntry(
      id: 'e_prev',
      kind: EntryKind.expense,
      amount: 85000,
      walletId: 'cash',
      categoryId: 'food',
      date: prevMonth,
      note: 'Ăn trưa tháng trước'));
  return p;
}

Widget _wrap(FinanceProvider p, {String? initialCategoryId}) => ChangeNotifierProvider.value(
    value: p, child: MaterialApp(theme: AppTheme.lightTheme, home: LedgerScreen(initialCategoryId: initialCategoryId)));

void main() {
  testWidgets('Tìm kiếm theo ghi chú, danh mục, đối tượng, số tiền và ví', (tester) async {
    final p = _seedProvider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    expect(find.text('6 giao dịch • VND'), findsOneWidget);
    expect(find.text('+2.000.000 ₫'), findsOneWidget);
    expect(find.text('−190.000 ₫'), findsOneWidget);

    final searchField = find.byType(TextField).first;

    await tester.enterText(searchField, 'cà phê');
    await tester.pumpAndSettle();
    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.textContaining('Cà phê sáng'), findsOneWidget);

    await tester.enterText(searchField, 'minh');
    await tester.pumpAndSettle();
    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.textContaining('Cho bạn mượn'), findsOneWidget);

    await tester.enterText(searchField, '120000');
    await tester.pumpAndSettle();
    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.textContaining('Đổ xăng xe máy'), findsOneWidget);

    await tester.enterText(searchField, 'ngân hàng acb');
    await tester.pumpAndSettle();
    expect(find.text('3 giao dịch • VND'), findsOneWidget);

    await tester.enterText(searchField, 'không tồn tại xyz');
    await tester.pumpAndSettle();
    expect(find.byType(EntryTile), findsNothing);
    expect(find.text('Không tìm thấy giao dịch'), findsOneWidget);
  });

  testWidgets('Lọc theo loại giao dịch và chuyển tháng', (tester) async {
    final p = _seedProvider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Chi tiêu'));
    await tester.pumpAndSettle();
    expect(find.text('3 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Cà phê sáng'), findsOneWidget);
    expect(find.textContaining('Đổ xăng xe máy'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Thu nhập'));
    await tester.pumpAndSettle();
    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Lương tháng này'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Chuyển tiền'));
    await tester.pumpAndSettle();
    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Rút tiền mặt'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Vay / Nợ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Vay / Nợ'));
    await tester.pumpAndSettle();
    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Cho bạn mượn'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Tất cả'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả'));
    await tester.pumpAndSettle();
    expect(find.text('6 giao dịch • VND'), findsOneWidget);

    await tester.tap(find.byTooltip('Tháng trước'));
    await tester.pumpAndSettle();
    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Ăn trưa tháng trước'), findsOneWidget);
  });

  testWidgets('Lọc nâng cao theo ví, danh mục, đối tượng và xóa bộ lọc', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = _seedProvider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_wrap(p));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();

    // Lọc theo ví đích + ví nguồn (Tiền mặt: coffee, transfer->cash, lend, excluded = 4 giao dịch)
    await tester.tap(find.byKey(const ValueKey('wallet-filter--VND')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiền mặt').last);
    await tester.pumpAndSettle();
    expect(find.text('4 giao dịch • VND'), findsOneWidget);

    // Lọc thêm theo danh mục Ăn uống (còn coffee + excluded = 2 giao dịch)
    await tester.tap(find.byKey(const ValueKey('category-filter-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ăn uống (chi)').last);
    await tester.pumpAndSettle();
    expect(find.text('2 giao dịch • VND'), findsOneWidget);

    // Xóa bộ lọc trả lại đủ 6 giao dịch
    await tester.tap(find.text('Xóa bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('6 giao dịch • VND'), findsOneWidget);

    // Lọc theo đối tượng Minh
    await tester.tap(find.byKey(const ValueKey('person-filter-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minh').last);
    await tester.pumpAndSettle();
    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Cho bạn mượn'), findsOneWidget);
  });

  testWidgets('Mở Sổ giao dịch với initialCategoryId lọc sẵn danh mục', (tester) async {
    final p = _seedProvider();
    addTearDown(p.dispose);
    await tester.pumpWidget(_wrap(p, initialCategoryId: 'transport'));
    await tester.pumpAndSettle();

    expect(find.text('1 giao dịch • VND'), findsOneWidget);
    expect(find.textContaining('Đổ xăng xe máy'), findsOneWidget);
  });
}
