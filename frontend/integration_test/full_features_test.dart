import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:finance_app/app/app.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/ai/presentation/receipt_scan_screen.dart';
import 'package:finance_app/features/ai/presentation/smart_search_screen.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/forgot_password_screen.dart';
import 'package:finance_app/features/goals/presentation/goals_screen.dart';
import 'package:finance_app/features/ledger/presentation/ledger_screen.dart';
import 'package:finance_app/features/recurring/presentation/recurring_screen.dart';
import 'package:finance_app/features/security/presentation/lock_screen.dart';
import 'package:finance_app/features/settings/data/excel_export.dart';
import 'package:finance_app/features/settings/presentation/others_screen.dart';
import 'package:finance_app/features/settings/presentation/settings_screens.dart';
import 'package:finance_app/features/statistics/presentation/statistics_screen.dart';
import 'package:finance_app/features/transactions/presentation/add_transaction_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_category_screen.dart';
import 'package:finance_app/features/transactions/presentation/select_person_screen.dart';
import 'package:finance_app/features/wallets/presentation/create_wallet_screen.dart';
import 'package:finance_app/features/wallets/presentation/wallet_detail_screen.dart';
import 'package:finance_app/features/wallets/presentation/wallets_screen.dart';

/// Kiểm thử toàn bộ chức năng trên thiết bị thật với backend + AI service thật.
///
/// 1. "Chức năng": đi qua đủ 9 nhóm chức năng của báo cáo và các chức năng mở rộng bằng sổ cái
///    của ứng dụng, đồng bộ lên máy chủ, mô phỏng thiết bị thứ hai đăng nhập cùng tài khoản.
/// 2. "Giao diện": mở lần lượt mọi màn hình trên thiết bị, chụp ảnh; bất kỳ lỗi dựng giao diện
///    nào (tràn bố cục, ngoại lệ) đều làm bài kiểm thử thất bại.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.now();
  final month = DateTime(now.year, now.month);
  DateTime ago(int days) => DateTime(now.year, now.month, now.day, 10).subtract(Duration(days: days));
  final email = 'full${now.millisecondsSinceEpoch % 1000000}@nhom3.vn';
  const pass1 = 'matkhau123', pass2 = 'matkhau456', pass3 = 'matkhau789';

  void expectRejected(void Function() action, String reason) {
    expect(action, throwsA(isA<ArgumentError>()), reason: reason);
  }

  testWidgets('Chức năng: 9 nhóm chức năng + mở rộng, đồng bộ hai thiết bị', (t) async {
    final p = FinanceProvider(storage: null, api: ApiClient());

    // ---------------------------------------------------------------- a) Tài khoản
    expect(await p.checkServer(), isNull, reason: 'backend phải chạy');
    await p.register(name: 'Kiểm Thử', email: email, password: pass1);
    expect(p.signedIn, isTrue);
    final code = await p.resendVerification();
    if (code != null) {
      await p.verifyEmail(code);
      expect(p.emailVerified, isTrue);
    }
    await p.changePassword(pass1, pass2);
    final other = FinanceProvider(storage: null, api: ApiClient());
    await expectLater(other.signIn(email: email, password: pass1), throwsA(isA<ApiException>()),
        reason: 'mật khẩu cũ không còn dùng được');
    final reset = await other.forgotPassword(email);
    expect(reset, isNotNull, reason: 'máy chủ dev trả mã khôi phục');
    await other.resetPassword(email: email, code: reset!, newPassword: pass3);
    expect(other.signedIn, isTrue);
    await other.signOut();
    // Đặt lại mật khẩu thu hồi mọi phiên cũ → thiết bị 1 đăng nhập lại bằng mật khẩu mới
    await p.syncNow();
    expect(p.syncError, isNotNull, reason: 'phiên cũ phải bị thu hồi sau khi đặt lại mật khẩu');
    await p.signOut(revoke: false);
    if (await p.signIn(email: email, password: pass3)) await p.resolveLogin(useAccount: true);
    expect(p.signedIn, isTrue);

    // ---------------------------------------------------------------- b) Ví
    p.saveWallet(const MoneyWallet(id: 'bank', name: 'Vietcombank', opening: 10000000));
    p.saveWallet(MoneyWallet(
        id: 'save', name: 'Tiết kiệm Laptop', savings: true, target: 20000000, startDate: month,
        deadline: DateTime(now.year + 1, now.month)));
    expectRejected(() => p.saveWallet(const MoneyWallet(id: 'dup', name: 'vietcombank')), 'trùng tên ví');
    p.saveWallet(const MoneyWallet(id: 'usd', name: 'Ví USD', currency: 'USD', opening: 100));
    expect(p.wallets.map((w) => w.id), containsAll(['cash', 'bank', 'save', 'usd']));

    // ---------------------------------------------------------------- d) Danh mục, e) Đối tượng
    p.saveCategory(const MoneyCategory('coffee', 'Cà phê', false, 3));
    p.saveCategory(const MoneyCategory('temp', 'Tạm thời', false, 5));
    p.deleteCategory('temp');
    expect(p.category('temp'), isNull);
    p.savePerson(const MoneyPerson('minh', 'Minh', 'Bạn bè & Đồng nghiệp'));
    p.savePerson(const MoneyPerson('lan', 'Lan', 'Bạn bè & Đồng nghiệp'));

    // ---------------------------------------------------------------- c) Giao dịch (đủ 9 loại)
    var n = 0;
    String id() => 'e${n++}';
    void add(EntryKind k, double amount, String wallet,
            {int day = 0, String? cat, String? person, String? to, String note = '', DateTime? due}) =>
        p.saveEntry(MoneyEntry(
            id: id(), kind: k, amount: amount, walletId: wallet, date: ago(day), categoryId: cat,
            personId: person, destinationId: to, note: note, dueDate: due));
    add(EntryKind.income, 18000000, 'bank', day: 1, cat: 'salary', note: 'Lương tháng');
    add(EntryKind.expense, 45000, 'cash', cat: 'food', note: 'Phở bò');
    add(EntryKind.expense, 35000, 'cash', cat: 'coffee', note: 'Highlands');
    add(EntryKind.expense, 5000000, 'bank', day: 2, cat: 'house', note: 'Tiền nhà');
    add(EntryKind.transfer, 2000000, 'bank', to: 'save', note: 'Để dành mua laptop');
    add(EntryKind.lend, 500000, 'cash', person: 'minh', note: 'Cho Minh mượn', due: ago(-7));
    add(EntryKind.collect, 200000, 'cash', person: 'minh', note: 'Minh trả một phần');
    add(EntryKind.interestIncome, 20000, 'cash', person: 'minh', cat: 'other_income', note: 'Lãi Minh trả');
    add(EntryKind.borrow, 1000000, 'bank', person: 'lan', note: 'Vay Lan', due: ago(-14));
    add(EntryKind.repay, 400000, 'bank', person: 'lan', note: 'Trả Lan');
    add(EntryKind.interestExpense, 10000, 'bank', person: 'lan', cat: 'life', note: 'Lãi trả Lan');
    expectRejected(() => add(EntryKind.collect, 400000, 'cash', person: 'minh'), 'thu nợ vượt số còn lại');
    expectRejected(() => add(EntryKind.lend, 100000, 'cash'), 'vay/nợ phải có đối tượng');
    expectRejected(() => add(EntryKind.expense, 0, 'cash', cat: 'food'), 'số tiền phải > 0');
    expectRejected(() => add(EntryKind.transfer, 1000, 'bank', to: 'usd'), 'chuyển tiền khác tiền tệ');
    expectRejected(() => p.deleteCategory('coffee'), 'không xóa danh mục đang dùng');
    expectRejected(() => p.deletePerson('minh'), 'không xóa đối tượng đang dùng');
    expectRejected(() => p.deleteWallet('save'), 'xóa ví có dữ liệu phải xác nhận xóa kèm');

    // Số dư = ban đầu + giao dịch (tính tay để đối chiếu)
    expect(p.balance('bank'), 10000000 + 18000000 - 5000000 - 2000000 + 1000000 - 400000 - 10000);
    expect(p.balance('save'), 2000000);
    expect(p.balance('cash'), -45000 - 35000 - 500000 + 200000 + 20000);
    expect(p.debt(borrowed: false, personId: 'minh'), 300000, reason: 'Minh còn nợ');
    expect(p.debt(borrowed: true, personId: 'lan'), 600000, reason: 'còn nợ Lan');

    // Sửa và xóa giao dịch
    final pho = p.entries.firstWhere((e) => e.note == 'Phở bò');
    p.saveEntry(MoneyEntry(id: pho.id, kind: pho.kind, amount: 50000, walletId: 'cash', date: pho.date,
        categoryId: 'food', note: 'Phở bò tái'));
    expect(p.entries.firstWhere((e) => e.id == pho.id).amount, 50000);

    // ---------------------------------------------------------------- f) Ngân sách
    p.saveBudget(MoneyBudget(id: 'b_all', categoryId: null, month: month, amount: 8000000));
    p.saveBudget(MoneyBudget(id: 'b_food', categoryId: 'food', month: month, amount: 2000000));
    p.saveBudget(MoneyBudget(id: 'b_in', categoryId: null, month: month, amount: 20000000, income: true));
    expectRejected(() => p.saveBudget(MoneyBudget(id: 'x', categoryId: 'food', month: month, amount: 1)),
        'trùng mục tiêu danh mục trong tháng');
    final foodBudget = p.budgets.firstWhere((b) => b.id == 'b_food');
    expect(p.used(foodBudget), p.total(month, income: false, categoryId: 'food'));
    final nextMonth = DateTime(month.year, month.month + 1);
    expect(p.copyBudgets(month, nextMonth), 3, reason: 'sao chép mục tiêu sang tháng sau');
    expect(p.copyBudgets(month, nextMonth), 0, reason: 'không sao chép trùng');

    // ---------------------------------------------------------------- Giao dịch định kỳ
    p.saveRecurring(RecurringRule(
        id: 'r_cf', kind: EntryKind.expense, amount: 29000, walletId: 'cash',
        frequency: RepeatFrequency.daily, startDate: ago(3), categoryId: 'coffee', note: 'Cà phê sáng'));
    final created = p.runRecurring();
    expect(created, greaterThanOrEqualTo(3), reason: 'tự ghi các lần đến hạn');
    expect(p.runRecurring(), 0, reason: 'không ghi trùng');

    // ---------------------------------------------------------------- g) Dashboard, h) Thống kê
    // Tính theo khoảng thời gian để không phụ thuộc ngày chạy (đầu tháng, giao dịch hôm qua thuộc tháng trước)
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final earned = p.sumBetween(ago(30), tomorrow, income: true);
    final spent = p.sumBetween(ago(30), tomorrow, income: false);
    expect(earned, 18000000 + 20000, reason: 'thu = lương + lãi (chuyển tiền, gốc vay không tính)');
    expect(spent, greaterThan(5000000 + 50000 + 35000 + 10000));
    expect(p.total(month, income: false) + p.total(DateTime(month.year, month.month - 1), income: false),
        greaterThanOrEqualTo(spent - 1e-6), reason: 'tổng theo tháng khớp tổng theo khoảng');
    expect(p.sumBetween(ago(400), now.add(const Duration(days: 1)), income: false, categoryId: 'coffee'),
        35000 + 29000 * created);

    // ---------------------------------------------------------------- i) Tìm kiếm & lọc
    final hits = p.entries.where((e) => e.note.toLowerCase().contains('phở')).toList();
    expect(hits, hasLength(1));
    expect(p.inMonth(month, walletId: 'save').every((e) => e.walletId == 'save' || e.destinationId == 'save'), isTrue);

    // ---------------------------------------------------------------- Mở rộng: tỷ giá, xuất dữ liệu, khóa PIN
    p.setRate('USD', 25000);
    expect(p.convertedTotal('VND'), closeTo(p.totalBalance('VND') + 100 * 25000, 1));
    final csv = p.exportCsv();
    expect(csv.split('\r\n').length, greaterThan(10));
    final xlsx = ExcelExport.build(p);
    expect(String.fromCharCodes(xlsx.take(2)), 'PK', reason: '.xlsx là tệp zip');
    final lock = AppLock();
    await lock.setPin('2468');
    lock.lock();
    expect(lock.unlock('1111'), isNotNull);
    expect(lock.unlock('2468'), isNull);
    for (var i = 0; i < 5; i++) {
      lock.unlock('0000');
    }
    expect(lock.blockedUntil, isNotNull, reason: 'chặn sau 5 lần sai');

    // ---------------------------------------------------------------- Đồng bộ + thiết bị thứ hai
    await p.syncNow();
    expect(p.syncError, isNull);
    expect(p.pendingChanges, 0);
    final device2 = FinanceProvider(storage: null, api: ApiClient());
    if (await device2.signIn(email: email, password: pass3)) await device2.resolveLogin(useAccount: true);
    expect(device2.entries.length, p.entries.length, reason: 'thiết bị 2 nhận đủ giao dịch');
    expect(device2.balance('bank'), p.balance('bank'));
    expect(device2.budgets.length, p.budgets.length);
    expect(device2.recurring.single.id, 'r_cf');
    device2.deleteEntry(pho.id);
    await device2.syncNow();
    await p.syncNow();
    expect(p.entries.any((e) => e.id == pho.id), isFalse, reason: 'xóa trên thiết bị 2 → thiết bị 1 cập nhật');

    // ---------------------------------------------------------------- AI qua backend
    final ai = AiRepository(p);
    final (parsed, remote) = await ai.parse('cho Lan mượn 300k hôm qua');
    expect(remote, isTrue);
    expect(parsed.kind, EntryKind.lend);
    expect(parsed.personId, 'lan', reason: 'nhận ra đối tượng đã có');
    final insights = await ai.insights();
    expect(insights?.forecast, isNotNull);
    final reply = await ai.chat([{'role': 'user', 'content': 'ai đang nợ mình?'}]);
    expect(reply.reply, contains('Minh'));
    final (ids, _) = await ai.search('cà phê tháng này');
    expect(ids, isNotEmpty);

    // ---------------------------------------------------------------- Xóa tài khoản
    await device2.signOut();
    await p.syncNow();
    expect(p.syncError, isNull, reason: 'đăng xuất thiết bị 2 không làm thiết bị 1 mất phiên');
    await p.deleteAccount(pass3);
    expect(p.signedIn, isFalse);
    await expectLater(device2.signIn(email: email, password: pass3), throwsA(isA<ApiException>()));
    for (final x in [p, other, device2]) {
      x.dispose();
    }
  });

  testWidgets('Giao diện: mở mọi màn hình không lỗi', (t) async {
    // Dữ liệu mẫu ngoại tuyến đủ để mọi màn hình có nội dung
    final p = FinanceProvider(storage: null, api: ApiClient());
    p.saveWallet(const MoneyWallet(id: 'bank', name: 'Vietcombank', opening: 10000000));
    p.saveWallet(MoneyWallet(id: 'save', name: 'Tiết kiệm', savings: true, target: 20000000, deadline: DateTime(now.year + 1)));
    p.savePerson(const MoneyPerson('minh', 'Minh', 'Bạn bè & Đồng nghiệp'));
    var i = 0;
    for (var d = 0; d < 40; d++) {
      p.saveEntry(MoneyEntry(id: 'u${i++}', kind: EntryKind.expense, amount: 30000.0 + d * 1000, walletId: 'cash',
          date: ago(d), categoryId: d.isEven ? 'food' : 'transport', note: d.isEven ? 'Cơm trưa' : 'Grab'));
    }
    p.saveEntry(MoneyEntry(id: 'u${i++}', kind: EntryKind.income, amount: 15000000, walletId: 'bank', date: ago(2), categoryId: 'salary'));
    p.saveEntry(MoneyEntry(id: 'u${i++}', kind: EntryKind.lend, amount: 500000, walletId: 'cash', date: ago(3), personId: 'minh', dueDate: ago(-2)));
    p.saveBudget(MoneyBudget(id: 'b1', categoryId: null, month: month, amount: 6000000));
    p.saveBudget(MoneyBudget(id: 'b2', categoryId: 'food', month: month, amount: 1500000));
    p.saveRecurring(RecurringRule(id: 'r1', kind: EntryKind.expense, amount: 5000000, walletId: 'bank',
        frequency: RepeatFrequency.monthly, startDate: DateTime(now.year, now.month, 5), categoryId: 'house', note: 'Tiền nhà'));

    await t.pumpWidget(FinanceApp(finance: p, lock: AppLock(), returning: true));
    await t.pumpAndSettle();
    expect(find.byType(MainScreen), findsOneWidget);
    final nav = Navigator.of(t.element(find.byType(MainScreen)));
    var shot = 0;
    Future<void> visit(String name, Widget page) async {
      nav.push(MaterialPageRoute<void>(builder: (_) => page));
      await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await t.pump();
      expect(t.takeException(), isNull, reason: 'màn $name dựng lỗi');
      if (!Platform.isAndroid) await binding.takeScreenshot('tour_${(shot++).toString().padLeft(2, '0')}_$name');
      nav.pop();
      await t.pumpAndSettle();
    }

    // Các tab chính
    for (final tab in ['Sổ giao dịch', 'Ngân sách', 'Tài khoản', 'Tổng quan']) {
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'tab $tab');
    }
    for (final tab in ['Sổ nợ', 'Ví', 'Báo cáo']) {
      await t.tap(find.text(tab).first);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'tab tổng quan $tab');
    }

    final pages = <String, Widget>{
      'thong_ke': const StatisticsScreen(),
      'so_giao_dich': const LedgerScreen(),
      'ngan_sach': const GoalsScreen(),
      'tai_khoan': const OthersScreen(),
      'vi': const WalletsScreen(),
      'chi_tiet_vi_tiet_kiem': const WalletDetailScreen(walletId: 'save'),
      'tao_vi': const CreateWalletScreen(),
      'them_chi': const AddTransactionScreen(),
      'them_thu': const AddTransactionScreen(initialKind: EntryKind.income),
      'chuyen_tien': const AddTransactionScreen(initialKind: EntryKind.transfer),
      'cho_vay': const AddTransactionScreen(initialKind: EntryKind.lend),
      'tra_lai': const AddTransactionScreen(initialKind: EntryKind.interestExpense),
      'chon_danh_muc': const SelectCategoryScreen(),
      'quan_ly_doi_tuong': const SelectPersonScreen(manage: true),
      'dinh_ky': const RecurringScreen(),
      'ty_gia': const RatesScreen(),
      'nhac_nho': const RemindersScreen(),
      'bao_mat': const SecurityScreen(),
      'dat_pin': const PinSetupScreen(),
      'xuat_du_lieu': const ExportScreen(),
      'phan_tich_ai': const InsightsScreen(),
      'tro_ly_ai': const AssistantScreen(),
      'quet_hoa_don': const ReceiptScanScreen(),
      'tim_kiem_ai': const SmartSearchScreen(),
      'dang_nhap': const AuthScreen(fromSettings: true),
      'quen_mat_khau': const ForgotPasswordScreen(),
    };
    for (final e in pages.entries) {
      await visit(e.key, e.value);
    }

    // Nhập nhanh (bottom sheet)
    await t.tap(find.byKey(const ValueKey('quick-entry-button')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('quick-entry')), 'cho Minh mượn 200k');
    await t.pumpAndSettle();
    expect(find.text('Cho vay'), findsWidgets);
    expect(t.takeException(), isNull);
    // FinanceApp tự giải phóng FinanceProvider khi cây widget bị gỡ.
  });
}
