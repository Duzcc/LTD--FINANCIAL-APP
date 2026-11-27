import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/services/notification_service.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/settings/presentation/screens/reminders_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  const mobile = TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS});
  final calls = <MethodCall>[];
  late bool granted;
  late bool allowRequest;

  setUp(() {
    granted = false;
    allowRequest = false;
    calls.clear();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
          return granted;
        case 'checkPermissions':
          return {'isEnabled': granted};
        case 'requestNotificationsPermission':
        case 'requestPermissions':
          granted = allowRequest;
          return granted;
        case 'pendingNotificationRequests':
          return [];
        default:
          return null;
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('Công tắc nhắc nhở phản ánh quyền thực tế trên điện thoại', (tester) async {
    final requestMethod =
        defaultTargetPlatform == TargetPlatform.iOS ? 'requestPermissions' : 'requestNotificationsPermission';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      IOSFlutterLocalNotificationsPlugin.registerWith();
    }
    final finance = FinanceProvider();
    finance.setReminders(debts: false);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: finance,
      child: const MaterialApp(home: RemindersScreen()),
    ));
    await tester.pumpAndSettle();

    Finder tile(String label) => find.widgetWithText(SwitchListTile, label);
    bool enabled(String label) => tester.widget<SwitchListTile>(tile(label)).value;
    const daily = 'Nhắc ghi chép hằng ngày';
    const debt = 'Nhắc hạn trả/thu nợ';
    const budget = 'Cảnh báo vượt ngân sách';
    expect(enabled(budget), isFalse);
    await tester.tap(tile(daily));
    await tester.pumpAndSettle();
    expect(finance.remindersEnabled, isFalse);
    expect(enabled(daily), isFalse);
    expect(find.textContaining('Chưa được cấp quyền'), findsOneWidget);

    allowRequest = true;
    await tester.tap(tile(debt));
    await tester.pumpAndSettle();
    expect(finance.debtReminders, isTrue);
    expect(enabled(debt), isTrue);
    expect(enabled(budget), isTrue);
    expect(calls.where((c) => c.method == requestMethod), hasLength(2));

    granted = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(enabled(debt), isFalse);
    expect(enabled(budget), isFalse);
    await tester.pumpWidget(const SizedBox());
    finance.dispose();
  }, variant: mobile);

  testWidgets('Lịch chỉ nhắc gốc còn nợ và chỉ gửi cảnh báo ngân sách khi được cấp quyền', (tester) async {
    final finance = FinanceProvider();
    final today = DateTime.now();
    final oldDate = DateTime(today.year, today.month, today.day - 5);
    final due = DateTime(today.year, today.month, today.day + 3);
    finance.savePerson(const MoneyPerson('an', 'An', 'Bạn bè'));

    void save(String id, EntryKind kind, double amount, DateTime date, {DateTime? deadline}) {
      finance.saveEntry(MoneyEntry(
        id: id,
        kind: kind,
        amount: amount,
        personId: 'an',
        walletId: 'cash',
        date: date,
        dueDate: deadline,
      ));
    }

    save('old', EntryKind.borrow, 100000, oldDate, deadline: due.add(const Duration(days: 1)));
    save('new', EntryKind.borrow, 200000, today, deadline: due);
    save('paid', EntryKind.repay, 150000, today);
    final service = NotificationService.instance;
    final budget = MoneyBudget(id: 'food', categoryId: 'food', month: today, amount: 100000);
    await service.apply(finance);
    await service.budgetExceeded(budget, 'Ăn uống', 20000);
    expect(calls.where((c) => c.method == 'zonedSchedule' || c.method == 'show'), isEmpty);

    granted = true;
    await service.apply(finance);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').map((c) => c.arguments as Map).toList();
    expect(scheduled, hasLength(2));
    expect(scheduled.map((n) => n['title']), everyElement('Đến hạn trả nợ An'));
    expect(scheduled.map((n) => n['body']), [
      'Ngày mai đến hạn, còn lại ${money(150000, 'VND')}.',
      'Hôm nay đến hạn, còn lại ${money(150000, 'VND')}.',
    ]);
    await service.budgetExceeded(budget, 'Ăn uống', 20000);
    final notification = calls.singleWhere((c) => c.method == 'show').arguments as Map;
    expect(notification['title'], 'Vượt ngân sách • Ăn uống');
    expect(notification['body'], contains(money(20000, 'VND')));
    await finance.flush();
    finance.dispose();
  }, variant: android);
}
