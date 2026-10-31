import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/features/ai/on_device/local_assistant.dart';
import 'package:finance_app/features/ai/on_device/category_model.dart';
import 'package:finance_app/features/ai/on_device/insights.dart';
import 'package:finance_app/features/ai/on_device/quick_parser.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/features/settings/data/excel_export.dart';

void main() {
  final now = DateTime(2026, 10, 20, 10);
  MoneyEntry spend(String id, double amount, String category, DateTime date,
          {String note = ''}) =>
      MoneyEntry(
          id: id,
          kind: EntryKind.expense,
          amount: amount,
          walletId: 'cash',
          categoryId: category,
          date: date,
          note: note);

  group('Giao dịch định kỳ', () {
    test('Sinh giao dịch hằng tháng, lùi về cuối tháng và không trùng', () {
      final p = FinanceProvider();
      p.saveRecurring(RecurringRule(
          id: 'rent',
          kind: EntryKind.expense,
          amount: 3000000,
          walletId: 'cash',
          categoryId: 'house',
          note: 'Tiền nhà',
          frequency: RepeatFrequency.monthly,
          startDate: DateTime(2026, 7, 31, 9)));
      expect(p.runRecurring(now: now), 3); // 31/7, 31/8, 30/9
      expect(p.entries.map((e) => e.date.day).toList()..sort(), [30, 31, 31]);
      expect(p.runRecurring(now: now), 0);
      expect(p.recurring.single.upcoming, DateTime(2026, 10, 31, 9));
      expect(p.runRecurring(now: DateTime(2026, 11, 1)), 1);
      expect(p.entries.every((e) => e.recurringId == 'rent'), isTrue);
      expect(() => p.deleteCategory('house'), throwsArgumentError);
      p.dispose();
    });

    test('Tự nạp tiết kiệm hằng tuần và dừng ở ngày kết thúc', () {
      final p = FinanceProvider();
      p.saveWallet(const MoneyWallet(id: 'save', name: 'Tiết kiệm', savings: true));
      p.saveRecurring(RecurringRule(
          id: 'auto',
          kind: EntryKind.transfer,
          amount: 100000,
          walletId: 'cash',
          destinationId: 'save',
          frequency: RepeatFrequency.weekly,
          startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 15)));
      expect(p.runRecurring(now: now), 3); // 1, 8, 15
      expect(p.balance('save'), 300000);
      expect(p.recurring.single.active, isFalse);
      p.dispose();
    });

    test('Quy tắc lỗi (ví bị xóa) được dừng kèm thông báo', () {
      final p = FinanceProvider();
      p.savePerson(const MoneyPerson('an', 'An', 'Bạn bè'));
      p.saveRecurring(RecurringRule(
          id: 'pay',
          kind: EntryKind.repay,
          amount: 100,
          walletId: 'cash',
          personId: 'an',
          frequency: RepeatFrequency.monthly,
          startDate: DateTime(2026, 10, 1)));
      expect(p.runRecurring(now: now), 0); // chưa có khoản vay nào để trả
      expect(p.recurringError, isNotNull);
      expect(p.recurring.single.active, isFalse);
      p.dispose();
    });
  });

  group('AI trên thiết bị', () {
    test('Nhập nhanh hiểu số tiền, ngày, loại và đối tượng', () {
      final p = FinanceProvider();
      p.savePerson(const MoneyPerson('minh', 'Minh', 'Bạn bè'));
      final q = QuickEntryParser(p);
      var r = q.parse('ăn phở 45k sáng nay', now: now);
      expect(r.kind, EntryKind.expense);
      expect(r.amount, 45000);
      expect(r.categoryId, 'food');
      expect(r.date.hour, 8);
      expect(r.note, 'Ăn phở sáng nay');

      r = q.parse('đổ xăng 70.000 hôm qua', now: now);
      expect(r.amount, 70000);
      expect(r.categoryId, 'transport');
      expect(r.date.day, 19);

      r = q.parse('lương tháng 12tr5', now: now);
      expect(r.kind, EntryKind.income);
      expect(r.amount, 12500000);
      expect(r.categoryId, 'salary');

      r = q.parse('cho Minh mượn 1,5tr', now: now);
      expect(r.kind, EntryKind.lend);
      expect(r.amount, 1500000);
      expect(r.personId, 'minh');

      r = q.parse('vay của Hoàng 2 triệu ngày 5', now: now);
      expect(r.kind, EntryKind.borrow);
      expect(r.amount, 2000000);
      expect(r.newPersonName, 'Hoàng');
      expect(r.date.day, 5);

      r = QuickEntryParser(FinanceProvider()).parse('cho Minh mượn 500k', now: now);
      expect(r.kind, EntryKind.lend);
      expect(r.newPersonName, 'Minh');
      r = q.parse('vay mình 200k', now: now);
      expect(r.newPersonName, isNull);

      r = q.parse('2 ly cà phê 60k', now: now);
      expect(r.amount, 60000);
      expect(r.categoryId, 'food');
      p.dispose();
    });

    test('Mô hình gợi ý danh mục học từ lịch sử của người dùng', () {
      final p = FinanceProvider();
      p.saveCategory(const MoneyCategory('pet', 'Thú cưng', false, 19));
      for (var i = 0; i < 4; i++) {
        p.saveEntry(spend('m$i', 200000, 'pet', now, note: 'Hạt cho Mướp'));
      }
      final model = CategoryModel.train(p.categories, p.entries);
      expect(model.suggest('mua hạt cho mướp', income: false), 'pet');
      expect(model.suggest('đi grab tới trường', income: false), 'transport');
      expect(model.suggest('thưởng tết', income: true), 'bonus');
      expect(foldVietnamese('Đường Phố – Ăn Uống!'), 'duong pho an uong');
      p.dispose();
    });

    test('Dự báo, bất thường và trợ lý trả lời bằng số liệu thật', () {
      final p = FinanceProvider();
      for (var m = 7; m <= 9; m++) {
        for (var d = 1; d <= 28; d += 3) {
          p.saveEntry(spend('h$m$d', 50000, 'food', DateTime(2026, m, d)));
        }
      }
      for (var d = 1; d <= 20; d++) {
        p.saveEntry(spend('c$d', 60000, 'food', DateTime(2026, 10, d)));
      }
      p.saveBudget(MoneyBudget(
          id: 'all', categoryId: null, month: DateTime(2026, 10), amount: 1300000));
      final insights = FinanceInsights(p, now: now);
      final f = insights.forecast();
      expect(f.spent, 1200000);
      expect(f.projected, greaterThan(1300000));
      expect(f.overBudget, isTrue);
      final all = insights.all();
      expect(all.first.level, InsightLevel.danger);
      expect(all.any((i) => i.title.contains('Ăn uống tăng')), isTrue);

      final a = LocalAssistant(p, now: now);
      expect(a.answer('Tháng này tôi đã chi bao nhiêu?'), contains('1.200.000'));
      expect(a.answer('dự báo cuối tháng'), contains('vượt mục tiêu'));
      expect(a.answer('chi cho ăn uống tháng này'), contains('Ăn uống'));
      p.dispose();
    });
  });

  test('Đầu tháng chưa có lịch sử: không đưa dự báo nhân thẳng dễ sai', () {
    final p = FinanceProvider();
    p.saveEntry(MoneyEntry(
        id: 'x', kind: EntryKind.expense, amount: 50000, walletId: 'cash', categoryId: 'food',
        date: DateTime(2026, 11, 1, 9)));
    final tips = FinanceInsights(p, now: DateTime(2026, 11, 1, 12)).all();
    expect(tips.first.title, 'Đang học thói quen chi tiêu của bạn');
    expect(FinanceInsights(p, now: DateTime(2026, 11, 5, 12)).all().first.title, startsWith('Dự báo chi tiêu'));
    p.dispose();
  });

  test('Tỷ giá quy đổi tổng tài sản nhiều tiền tệ', () {
    final p = FinanceProvider();
    p.saveWallet(const MoneyWallet(id: 'usd', name: 'USD', currency: 'USD', opening: 100));
    p.saveWallet(const MoneyWallet(id: 'cash', name: 'Tiền mặt', opening: 500000));
    p.setRate('USD', 25000);
    expect(p.hasManyCurrencies, isTrue);
    expect(p.convertedTotal('VND'), 3000000);
    expect(p.convert(3000000, 'VND', 'USD'), 120);
    expect(() => p.setRate('USD', 0), throwsArgumentError);
    p.dispose();
  });

  test('Xuất Excel tạo tệp xlsx hợp lệ có 3 trang', () {
    final p = FinanceProvider();
    p.saveEntry(spend('e', 45000, 'food', now, note: 'Phở & <trà>'));
    final bytes = ExcelExport.build(p);
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet3.xml']));
    final sheet =
        utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('Phở &amp; &lt;trà&gt;'));
    expect(sheet, contains('<v>45000.0</v>'));
    p.dispose();
  });

  test('Khóa PIN: băm có muối, khóa tạm sau 5 lần sai', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final lock = AppLock(storage: storage);
    expect(lock.enabled, isFalse);
    await lock.setPin('2468');
    expect(storage.getString(AppLock.key), isNot(contains('2468')));
    final again = AppLock(storage: storage);
    expect(again.locked, isTrue);
    for (var i = 0; i < 4; i++) {
      expect(again.unlock('0000', now: now), contains('không đúng'));
    }
    expect(again.unlock('0000', now: now), contains('30 giây'));
    expect(again.unlock('2468', now: now), contains('Thử lại'));
    expect(again.unlock('2468', now: now.add(const Duration(seconds: 31))), isNull);
    expect(again.locked, isFalse);
    await again.disable();
    expect(storage.containsKey(AppLock.key), isFalse);
  });
}
