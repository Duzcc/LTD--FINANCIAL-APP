import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:finance_app/features/transactions/presentation/widgets/entry_tile.dart';

void main() {
  testWidgets('Bấm vào danh mục tháng trước chỉ hiện giao dịch tạo nên số trên biểu đồ', (tester) async {
    final finance = FinanceProvider();
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month, 0, 23, 59);
    finance.saveWallet(const MoneyWallet(id: 'usd', name: 'Đô la', currency: 'USD'));

    void expense(String id, DateTime date, double amount, {String wallet = 'cash', bool excluded = false}) {
      finance.saveEntry(
        MoneyEntry(
          id: id,
          kind: EntryKind.expense,
          date: date,
          categoryId: 'food',
          walletId: wallet,
          amount: amount,
          excluded: excluded,
        ),
      );
    }

    expense('breakfast', DateTime(lastDay.year, lastDay.month), 20000);
    expense('dinner', lastDay, 30000);
    expense('adjustment', lastDay, 90000, excluded: true);
    expense('dollars', lastDay, 10, wallet: 'usd');
    expense('next-month', DateTime(now.year, now.month), 45000);
    await finance.flush();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: finance,
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kỳ trước'));
    await tester.pumpAndSettle();
    expect(find.text(money(50000, 'VND')), findsWidgets);

    final category = find.widgetWithText(ListTile, 'Ăn uống').hitTestable();
    await tester.scrollUntilVisible(category, 240, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(category);
    await tester.pumpAndSettle();

    expect(find.text('2 giao dịch • Tổng chi'), findsOneWidget);
    expect(find.text(money(50000, 'VND')), findsOneWidget);
    expect(
      tester.widgetList<EntryTile>(find.byType(EntryTile)).map((tile) => tile.entry.id),
      ['dinner', 'breakfast'],
    );
  });
}
