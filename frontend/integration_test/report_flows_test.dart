// Chạy lại các luồng trong báo cáo (2.4.4, 2.4.5, 2.5) bằng thao tác trên giao diện.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:finance_app/app/app.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:finance_app/features/transactions/presentation/screens/add_transaction_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallet_detail_screen.dart';
import 'package:finance_app/features/wallets/presentation/screens/wallets_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
  final email = 'luong$stamp@nhom3.vn';
  const password = 'matkhau123';
  final canShoot = defaultTargetPlatform != TargetPlatform.android;
  var shots = 0;

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    await t.pumpAndSettle(
        const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
    await Future<void>.delayed(Duration(milliseconds: ms));
    await t.pump();
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t, 200);
    if (canShoot) await binding.takeScreenshot('${(++shots).toString().padLeft(2, '0')}_$name');
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    for (final delta in [-250.0, 250.0]) {
      if (f.evaluate().isNotEmpty) break;
      try {
        final vertical = find.byWidgetPredicate(
            (w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up));
        await t.scrollUntilVisible(f, delta, scrollable: vertical.hitTestable().first, maxScrolls: 30);
      } on StateError {
        // chiều này không thấy thì thử chiều kia
      }
    }
    await t.ensureVisible(f.last);
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f.last);
    await settle(t);
  }

  Future<void> tapText(WidgetTester t, String text) => tap(t, find.text(text));

  Future<void> type(WidgetTester t, Finder field, String text) async {
    await reveal(t, field);
    await t.enterText(field.last, text);
    await settle(t, 150);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> back(WidgetTester t) async {
    await t.pageBack();
    await settle(t);
  }

  Future<void> confirmDelete(WidgetTester t) async {
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Xóa')).last);
    await settle(t);
  }

  Future<void> tab(WidgetTester t, String label) async {
    await t.tap(find.descendant(of: find.byType(MainScreen), matching: find.text(label)).last);
    await settle(t);
  }

  testWidgets('Các luồng trong báo cáo, thao tác trên giao diện', (t) async {
    final p = FinanceProvider(storage: null, api: ApiClient());
    final signup = await p.register(name: 'Kiểm Thử Luồng', email: email, password: password);
    expect(signup.devCode, isNotNull, reason: 'máy chủ thử nghiệm trả mã OTP');
    await p.verifyOtp(signup, signup.devCode!);
    expect(p.signedIn, isTrue);

    await t.pumpWidget(FinanceApp(finance: p, returning: true));
    await settle(t, 1000);
    expect(find.byType(MainScreen), findsOneWidget);

    // Test flow 1 / Bảng 22–23: quản lý ví
    await tap(t, find.byKey(const ValueKey('open-drawer')));
    await tapText(t, 'Ví của tôi');
    await tap(t, find.widgetWithText(FilledButton, 'Thêm ví'));
    await tap(t, find.text('Lưu ví'));
    expect(find.text('Nhập tên ví'), findsOneWidget, reason: 'thiếu tên ví thì báo lỗi và không lưu');
    expect(p.wallets.length, 1);

    await type(t, field('Tên ví'), 'Ngân hàng');
    await tap(t, find.byKey(const ValueKey('wallet-icon-picker')));
    await tap(t, find.byKey(const ValueKey('wallet-icon-3')));
    await type(t, field('Số dư hiện có'), '5000000');
    await shot(t, 'tao_vi_co_ban');
    await tapText(t, 'Lưu ví');
    final bank = p.wallets.singleWhere((w) => w.name == 'Ngân hàng');
    expect(bank.symbol, 3);
    expect(p.balance(bank.id), 5000000);

    await tap(t, find.widgetWithText(FilledButton, 'Thêm ví'));
    await type(t, field('Tên ví'), 'ngân hàng');
    await tapText(t, 'Lưu ví');
    expect(find.text('Tên ví đã tồn tại. Vui lòng đặt tên khác.'), findsOneWidget);
    await type(t, field('Tên ví'), 'Heo đất');
    await tapText(t, 'Ví tiết kiệm');
    await type(t, field('Mục tiêu tiết kiệm'), '10000000');
    await tap(t, find.byKey(const ValueKey('wallet-notify')));
    await shot(t, 'tao_vi_tiet_kiem');
    await tapText(t, 'Lưu ví');
    final pig = p.wallets.singleWhere((w) => w.name == 'Heo đất');
    expect((pig.savings, pig.target, pig.notify), (true, 10000000.0, true));

    await tap(t, find.text('Chỉ tính tài sản có thể dùng ngay'));
    await shot(t, 'danh_sach_vi');
    await tap(t, find.text('Chỉ tính tài sản có thể dùng ngay'));

    await tapText(t, 'Ngân hàng');
    expect(find.byType(WalletDetailScreen), findsOneWidget);
    await tap(t, find.byTooltip('Chỉnh sửa ví'));
    await type(t, field('Tên ví'), 'Ngân hàng ACB');
    await tapText(t, 'Lưu ví');
    expect(p.wallet(bank.id).name, 'Ngân hàng ACB');
    await back(t);

    final cash = p.wallets.singleWhere((w) => w.name == 'Tiền mặt');
    await tap(t, find.widgetWithText(WalletCard, 'Tiền mặt'));
    await tap(t, find.byKey(const ValueKey('adjust-balance')));
    await t.enterText(find.byKey(const ValueKey('adjust-actual')), '300000');
    await settle(t, 150);
    expect(find.textContaining('Sẽ ghi một khoản thu'), findsOneWidget);
    await shot(t, 'dieu_chinh_so_du');
    await tapText(t, 'Lưu điều chỉnh');
    expect(p.balance(cash.id), 300000);
    expect(p.entries.singleWhere((e) => e.walletId == cash.id).excluded, isTrue,
        reason: 'khoản điều chỉnh không tính vào báo cáo');
    expect(find.text('Số dư cuối mỗi tháng'), findsOneWidget);
    await back(t);

    await tap(t, find.widgetWithText(WalletCard, 'Heo đất'));
    await tap(t, find.byKey(const ValueKey('savings-deposit')));
    expect(find.byType(AddTransactionScreen), findsOneWidget);
    await t.enterText(
        find.descendant(of: find.byKey(const ValueKey('transaction-amount')), matching: find.byType(EditableText)),
        '100000');
    await settle(t, 150);
    await tapText(t, 'Lưu giao dịch');
    expect((p.balance(pig.id), p.balance(cash.id)), (100000.0, 200000.0), reason: 'nạp tiền từ Tiền mặt vào Heo đất');
    await back(t);
    // thông báo vừa hiện che mất nút ở cuối danh sách
    for (final m in t.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      m.clearSnackBars();
    }
    await settle(t);

    await tap(t, find.widgetWithText(FilledButton, 'Thêm ví'));
    await type(t, field('Tên ví'), 'Ví tạm');
    await tapText(t, 'Lưu ví');
    final temp = p.wallets.singleWhere((w) => w.name == 'Ví tạm');
    await tapText(t, 'Ví tạm');
    await tap(t, find.byTooltip('Chỉnh sửa ví'));
    await tapText(t, 'Xóa ví');
    await confirmDelete(t);
    expect(p.findWallet(temp.id), isNull, reason: 'xóa ví sau khi xác nhận');
    await settle(t);
    if (find.byType(WalletDetailScreen).evaluate().isNotEmpty) await back(t);
    await back(t);

    // Test flow 2: quản lý danh mục
    await t.tap(find.byKey(const ValueKey('open-drawer')));
    await settle(t);
    await tapText(t, 'Danh mục');
    await tapText(t, 'Danh mục mới');
    await tapText(t, 'Lưu');
    expect(find.text('Vui lòng nhập tên danh mục'), findsOneWidget);
    await type(t, find.widgetWithText(TextFormField, 'Tên danh mục'), 'Cà phê');
    await tapText(t, 'Lưu');
    final coffee = p.categories.singleWhere((c) => c.name == 'Cà phê');
    expect(coffee.income, isFalse);
    await tapText(t, 'Thu nhập');
    await tapText(t, 'Danh mục mới');
    await type(t, find.widgetWithText(TextFormField, 'Tên danh mục'), 'Thưởng dự án');
    await tapText(t, 'Lưu');
    final bonus = p.categories.singleWhere((c) => c.name == 'Thưởng dự án');
    expect(bonus.income, isTrue);
    await shot(t, 'danh_muc_thu_nhap');
    final menu = find.descendant(
        of: find.ancestor(of: find.text('Thưởng dự án'), matching: find.byType(ListTile)),
        matching: find.byType(PopupMenuButton<String>));
    await tap(t, menu);
    await tapText(t, 'Chỉnh sửa');
    await type(t, find.widgetWithText(TextFormField, 'Tên danh mục'), 'Thưởng KPI');
    await tapText(t, 'Lưu');
    expect(p.category(bonus.id)!.name, 'Thưởng KPI');
    await tap(
        t,
        find.descendant(
            of: find.ancestor(of: find.text('Thưởng KPI'), matching: find.byType(ListTile)),
            matching: find.byType(PopupMenuButton<String>)));
    await tapText(t, 'Xóa');
    await confirmDelete(t);
    expect(p.category(bonus.id), isNull);
    await back(t);

    // Test flow 3 / Bảng 25–27: ghi nhận, sửa, xóa giao dịch thu chi
    Future<void> openAdd() async {
      await t.tap(find.descendant(of: find.byType(MainScreen), matching: find.byIcon(Icons.add)).last);
      await settle(t);
      expect(find.byType(AddTransactionScreen), findsOneWidget);
    }

    Future<void> pickWallet(String name) async {
      await tapText(t, 'Ví thanh toán');
      await tap(t, find.descendant(of: find.byType(BottomSheet), matching: find.text(name)));
    }

    await openAdd();
    await tapText(t, 'Lưu giao dịch');
    expect(find.text('Nhập số tiền lớn hơn 0'), findsOneWidget);
    await tapText(t, '+20k');
    await tapText(t, '+50k');
    final amountField = find.byKey(const ValueKey('transaction-amount'));
    await reveal(t, amountField);
    final amountText =
        t.widget<EditableText>(find.descendant(of: amountField, matching: find.byType(EditableText))).controller.text;
    expect(parseAmount(amountText), 70000, reason: 'nút cộng nhanh cộng dồn vào số tiền');
    await tapText(t, 'Cà phê');
    await pickWallet('Ngân hàng ACB');
    await type(t, find.byKey(const ValueKey('transaction-note')), 'Cà phê sáng');
    await shot(t, 'them_chi_tieu');
    await tapText(t, 'Lưu giao dịch');
    expect(find.text('Đã lưu giao dịch chi tiêu.'), findsOneWidget);
    expect(p.balance(bank.id), 5000000 - 70000);

    await openAdd();
    await tapText(t, 'Thu nhập');
    await type(t, find.byKey(const ValueKey('transaction-amount')), '2000000');
    await tapText(t, 'Lương');
    await pickWallet('Ngân hàng ACB');
    await tapText(t, 'Lưu giao dịch');
    expect(p.balance(bank.id), 5000000 - 70000 + 2000000);

    await openAdd();
    await type(t, find.byKey(const ValueKey('transaction-amount')), '15000');
    await back(t);
    expect(find.text('Bỏ thay đổi?'), findsOneWidget, reason: 'đóng biểu mẫu khi đã nhập thì hỏi lại');
    await tapText(t, 'Bỏ thay đổi');
    expect(find.byType(AddTransactionScreen), findsNothing);

    await tab(t, 'Sổ giao dịch');
    await type(t, find.byType(TextField).first, 'cà phê sáng');
    await shot(t, 'so_giao_dich_tim_kiem');
    await tap(t, find.textContaining('Cà phê sáng'));
    await type(t, find.byKey(const ValueKey('transaction-amount')), '90000');
    await tapText(t, 'Lưu giao dịch');
    expect(find.text('Đã cập nhật giao dịch.'), findsOneWidget);
    expect(p.balance(bank.id), 5000000 - 90000 + 2000000, reason: 'sửa giao dịch cập nhật số dư');
    FocusManager.instance.primaryFocus?.unfocus();
    t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await settle(t);
    await tap(t, find.textContaining('Cà phê sáng'));
    expect(find.byType(AddTransactionScreen), findsOneWidget, reason: 'chạm giao dịch mở màn chi tiết');
    await tapText(t, 'Xóa giao dịch');
    await confirmDelete(t);
    expect(p.balance(bank.id), 5000000 + 2000000, reason: 'xóa giao dịch hoàn lại số dư');
    await type(t, find.byType(TextField).first, '');

    // Luồng 3 / Bảng 29: vay nợ và Sổ nợ
    await tab(t, 'Tổng quan');
    await t.tap(find.widgetWithText(Tab, 'Sổ nợ'));
    await settle(t);
    await tapText(t, 'Thêm cho vay');
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cho vay')).selected, isTrue);
    await type(t, find.byKey(const ValueKey('transaction-amount')), '500000');
    await pickWallet('Ngân hàng ACB');
    await tapText(t, 'Đối tượng (người vay / cho vay)');
    await tapText(t, 'Đối tượng mới');
    await t.enterText(find.byType(TextFormField).last, 'Minh');
    await tapText(t, 'Lưu');
    await tapText(t, 'Bạn bè & Đồng nghiệp');
    await tapText(t, 'Minh');
    await tapText(t, 'Lưu giao dịch');
    final minh = p.people.singleWhere((x) => x.name == 'Minh');
    expect(p.debt(borrowed: false, personId: minh.id, unit: 'VND'), 500000);
    expect(p.balance(bank.id), 7000000 - 500000);
    await tapText(t, 'Xem theo người');
    await tap(t, find.widgetWithText(ExpansionTile, 'Minh'));
    await shot(t, 'so_no_theo_nguoi');

    await tapText(t, 'Thu nợ');
    await type(t, find.byKey(const ValueKey('transaction-amount')), '700000');
    await tapText(t, 'Lưu giao dịch');
    expect(find.text('Số tiền thu nợ vượt số còn phải thu.'), findsOneWidget);
    await tap(t, find.textContaining('Điền toàn bộ'));
    await tapText(t, 'Lưu giao dịch');
    expect(p.debt(borrowed: false, personId: minh.id, unit: 'VND'), 0);
    expect(p.balance(bank.id), 7000000);
    expect(find.text('Đã tất toán'), findsWidgets);

    // Luồng 2 / Bảng 32: ngân sách
    await openAdd();
    await type(t, find.byKey(const ValueKey('transaction-amount')), '120000');
    await tapText(t, 'Cà phê');
    await pickWallet('Ngân hàng ACB');
    await tapText(t, 'Lưu giao dịch');

    await tab(t, 'Ngân sách');
    await tap(t, find.byTooltip('Sửa mục tiêu tháng'));
    await t.enterText(find.byType(TextFormField).last, '0');
    await tapText(t, 'Lưu');
    expect(find.text('Nhập số tiền lớn hơn 0'), findsOneWidget, reason: 'mục tiêu bằng 0 báo lỗi ngay tại ô');
    await t.enterText(find.byType(TextFormField).last, '3000000');
    await tapText(t, 'Lưu');
    expect(p.overallBudget(DateTime(DateTime.now().year, DateTime.now().month), income: false)?.amount, 3000000);

    await tap(t, find.byKey(ValueKey('unset-${coffee.id}')));
    await type(t, field('Số tiền mục tiêu'), '100000');
    await tapText(t, 'Lưu mục tiêu');
    final coffeeBudget = p.budgets.singleWhere((b) => b.categoryId == coffee.id);
    expect(coffeeBudget.amount, 100000);
    final over = find.text('Vượt ${money(20000, 'VND')}');
    await reveal(t, over);
    expect(over, findsOneWidget, reason: 'chi 120.000 trên hạn mức 100.000');
    await shot(t, 'ngan_sach_vuot');
    await tap(
        t, find.descendant(of: find.byKey(ValueKey(coffeeBudget.id)), matching: find.byType(PopupMenuButton<String>)));
    await tapText(t, 'Xóa');
    await confirmDelete(t);
    expect(p.budgets.where((b) => b.categoryId == coffee.id), isEmpty);

    // Bảng 20: Tổng quan
    await tab(t, 'Tổng quan');
    await t.tap(find.widgetWithText(Tab, 'Báo cáo'));
    await settle(t);
    await tap(t, find.byTooltip('Ẩn số dư'));
    expect(p.hideBalance, isTrue);
    expect(find.text(money(p.totalBalance('VND'), 'VND')), findsNothing, reason: 'ẩn số dư thì che số tiền');
    await shot(t, 'tong_quan_an_so_du');
    await tap(t, find.byTooltip('Hiện số dư'));
    await tapText(t, 'Xem báo cáo');
    expect(find.byType(StatisticsScreen), findsOneWidget);
    await shot(t, 'thong_ke');
    await back(t);

    // Bảng 34 + 2.5: đồng bộ và dữ liệu trên máy chủ thống nhất
    await tab(t, 'Tài khoản');
    await p.syncNow();
    await settle(t);
    expect(p.syncError, isNull);
    expect(p.pendingChanges, 0);
    await shot(t, 'tai_khoan_dong_bo');

    final device2 = FinanceProvider(storage: null, api: ApiClient());
    final login = await device2.signIn(email: email, password: password);
    if (await device2.verifyOtp(login, login.devCode!)) await device2.resolveLogin(useAccount: true);
    expect(device2.wallets.map((w) => w.name).toSet(), {'Tiền mặt', 'Ngân hàng ACB', 'Heo đất'});
    expect(device2.balance(bank.id), p.balance(bank.id));
    expect((device2.balance(cash.id), device2.balance(pig.id)), (200000.0, 100000.0));
    expect(device2.findWallet(pig.id)!.notify, isTrue);
    expect(device2.findWallet(bank.id)!.symbol, 3);
    expect(device2.entries.length, p.entries.length);
    expect(device2.categories.any((c) => c.name == 'Cà phê'), isTrue);
    expect(device2.overallBudget(DateTime(DateTime.now().year, DateTime.now().month), income: false)?.amount, 3000000);
    await device2.signOut();
    await p.deleteAccount(password);
  });
}
