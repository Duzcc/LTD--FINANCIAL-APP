import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'package:finance_app/features/ai/domain/entities/ai_models.dart';
import 'package:finance_app/features/ai/domain/services/local_assistant.dart';
import 'package:finance_app/features/ai/domain/services/receipt_parser.dart';
import 'package:finance_app/features/ai/domain/services/receipt_split.dart';
import 'package:finance_app/features/ai/domain/services/reminder_parser.dart';
import 'package:finance_app/features/ai/domain/services/spending_coach.dart';
import 'package:finance_app/features/ai/presentation/assistant_screen.dart';
import 'package:finance_app/features/ai/presentation/widgets/receipt_review_card.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';

void main() {
  final now = DateTime(2026, 10, 20, 10);

  MoneyEntry spend(String id, double amount, String category, DateTime date, {String note = ''}) => MoneyEntry(
      id: id, kind: EntryKind.expense, amount: amount, walletId: 'cash', categoryId: category, date: date, note: note);

  group('Nhắc nhở bằng câu tự nhiên', () {
    final parser = ReminderParser(now: now);

    test('Ngày trong tháng lặp hằng tháng, không nhầm "15 hàng" thành 15 giờ', () {
      final r = parser.parse('Nhắc tôi đóng tiền điện ngày 15 hàng tháng')!;
      expect(r.title, 'Đóng tiền điện');
      expect(r.repeat, ReminderRepeat.monthly);
      expect(r.at, DateTime(2026, 11, 15, 9));
    });

    test('Ngày mai kèm giờ buổi tối', () {
      final r = parser.parse('nhắc mình trả nợ chị Mai 200k tối mai lúc 8h30')!;
      expect(r.title, 'Trả nợ chị Mai 200k');
      expect(r.at, DateTime(2026, 10, 21, 20, 30));
      expect(r.repeat, ReminderRepeat.none);
    });

    test('Giờ đã qua trong ngày thì chuyển sang hôm sau', () {
      expect(parser.parse('nhắc tôi ghi chi tiêu lúc 7:00 hằng ngày')!.at, DateTime(2026, 10, 21, 7));
    });

    test('Không coi câu về nhạc hay giao dịch là nhắc nhở', () {
      expect(parser.parse('mua vé ca nhạc 500k'), isNull);
      expect(parser.parse('ăn phở 45k'), isNull);
    });

    test('Nhắc nhở hằng tháng tính lần tới và lưu cục bộ', () {
      final p = FinanceProvider();
      final r = SpendingReminder(id: 'r', title: 'Tiền nhà', at: DateTime(2026, 1, 31, 9), repeat: ReminderRepeat.monthly);
      expect(r.nextAfter(now), DateTime(2026, 10, 31, 9));
      expect(SpendingReminder(id: 'x', title: 'a', at: DateTime(2026, 1, 31, 9), repeat: ReminderRepeat.monthly)
          .nextAfter(DateTime(2026, 2, 5)), DateTime(2026, 2, 28, 9));
      p.saveReminder(r);
      expect(SpendingReminder.fromJson(p.reminders.single.toJson()).repeat, ReminderRepeat.monthly);
      expect(() => p.saveReminder(SpendingReminder(id: 'e', title: ' ', at: now)), throwsArgumentError);
      p.dispose();
    });
  });

  group('Hóa đơn tách theo danh mục', () {
    test('Đọc số lượng và đơn giá từ dòng hàng', () {
      final r = parseReceipt('WINMART\nSữa tươi Vinamilk 1L\n3 32.000 96.000\nDầu gội Clear\n1 x 89.000 89.000\n'
          'Tổng cộng 185.000');
      expect([for (final i in r.items) (i.name, i.quantity, i.unitPrice, i.amount)], [
        ('Sữa tươi Vinamilk 1L', 3.0, 32000.0, 96000.0),
        ('Dầu gội Clear', 1.0, 89000.0, 89000.0),
      ]);
    });

    test('Chia giảm giá theo tỷ lệ, tổng các khoản đúng bằng số phải trả', () {
      const items = [
        ReceiptItem('Sữa tươi', 96000, categoryId: 'food'),
        ReceiptItem('Bánh quy', 35000, categoryId: 'food'),
        ReceiptItem('Dầu gội', 89000, categoryId: 'life'),
      ];
      final groups = splitReceipt(items, 200000, 'food');
      expect(groups.map((g) => g.categoryId), ['food', 'life']);
      expect(groups.fold(0.0, (s, g) => s + g.amount), 200000);
      expect(groups.last.amount, 80909);
      expect(groups.first.note('WINMART'), 'WINMART: Sữa tươi, Bánh quy');
    });

    test('Dòng hàng lệch xa tổng thì ghi một khoản', () {
      final groups = splitReceipt(const [ReceiptItem('A', 5000, categoryId: 'life')], 100000, 'food');
      expect(groups.single.categoryId, 'food');
      expect(groups.single.amount, 100000);
    });

    test('Kết quả đọc trên máy gán danh mục cho từng món', () {
      final p = FinanceProvider();
      final r = AiRepository(p).parseLocally('BACH HOA XANH\nThịt heo 85.000\nBột giặt Omo 120.000\nTổng cộng 205.000');
      expect([for (final i in r.items) i.categoryId], ['food', 'life']);
      p.dispose();
    });

    testWidgets('Thẻ hóa đơn trong chat ghi mỗi danh mục một khoản, đổi được danh mục', (tester) async {
      final p = FinanceProvider();
      List<MoneyEntry>? saved;
      final receipt = ReceiptResult(
          merchant: 'WINMART',
          total: 185000,
          date: DateTime(2026, 10, 18, 19, 32),
          confidence: .9,
          source: 'thử nghiệm',
          items: const [
            ReceiptItem('Sữa tươi Vinamilk', 96000, quantity: 3, unitPrice: 32000, categoryId: 'food'),
            ReceiptItem('Dầu gội Clear', 89000, categoryId: 'food'),
          ]);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: p,
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: ReceiptReviewCard(
                          receipt: receipt, imagePath: '/tmp/hoa_don.jpg', onSaved: (e) => saved = e))))));
      expect(find.text('3 × 32.000 ₫'), findsOneWidget);
      expect(find.text('Ghi khoản chi'), findsOneWidget);
      await tester.tap(find.text('Ăn uống').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sinh hoạt').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ghi 2 khoản chi'));
      await tester.pumpAndSettle();
      expect(saved, hasLength(2));
      final byCategory = {for (final e in p.entries) e.categoryId: e};
      expect(byCategory['food']!.amount, 96000);
      expect(byCategory['life']!.amount, 89000);
      expect(byCategory['life']!.note, 'WINMART: Dầu gội Clear');
      expect(byCategory['life']!.date, DateTime(2026, 10, 18, 19, 32));
      expect(byCategory['life']!.photo, '/tmp/hoa_don.jpg');
      p.dispose();
    });
  });

  group('Hóa đơn khoản thu', () {
    test('Hóa đơn hoàn tiền đọc trên máy thành khoản thu với danh mục thu', () {
      final p = FinanceProvider();
      final r = AiRepository(p).parseLocally('SHOPEE\nHoàn tiền đơn hàng 250.000\nTổng cộng 250.000');
      expect(r.kind, EntryKind.income);
      expect(p.category(r.categoryId)?.income ?? true, isTrue);
      expect([for (final i in r.items) p.category(i.categoryId)?.income ?? true], everyElement(isTrue));
      p.dispose();
    });

    testWidgets('Thẻ hóa đơn đổi sang khoản thu thì ghi vào thu nhập', (tester) async {
      final p = FinanceProvider();
      final receipt = ReceiptResult(
          merchant: 'SHOPEE', total: 250000, date: DateTime(2026, 10, 18, 9), confidence: .9, source: 'thử nghiệm');
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: p,
          child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                  body: SingleChildScrollView(child: ReceiptReviewCard(receipt: receipt, onSaved: (_) {}))))));
      expect(find.text('Ghi khoản chi'), findsOneWidget);
      await tester.tap(find.text('Khoản thu'));
      await tester.pumpAndSettle();
      expect(find.text('Tổng nhận được'), findsOneWidget);
      await tester.tap(find.text('Ghi khoản thu'));
      await tester.pumpAndSettle();
      final e = p.entries.single;
      expect(e.kind, EntryKind.income);
      expect(e.amount, 250000);
      expect(p.category(e.categoryId)!.income, isTrue);
      p.dispose();
    });
  });

  group('Gợi ý và truy xuất chi tiêu', () {
    test('Mức được chi mỗi ngày theo ngân sách tổng và cảnh báo vượt danh mục', () {
      final p = FinanceProvider();
      p.saveBudget(MoneyBudget(id: 'all', categoryId: null, month: DateTime(2026, 10), amount: 6000000));
      p.saveBudget(MoneyBudget(id: 'food', categoryId: 'food', month: DateTime(2026, 10), amount: 1000000));
      p.saveEntry(spend('a', 1200000, 'food', DateTime(2026, 10, 5)));
      p.saveEntry(spend('b', 300000, 'transport', DateTime(2026, 10, 20, 8)));
      final coach = SpendingCoach(p, now: now);
      final a = coach.allowance()!;
      expect(a.daysLeft, 12);
      expect(a.daily, 400000);
      expect(a.leftToday, 100000);
      expect(coach.allowanceText(), contains('Ăn uống đã vượt ngân sách'));
      expect(coach.budgetWarnings({'food'}).first, contains('Ăn uống đã vượt'));
      expect(LocalAssistant(p, now: now).answer('hôm nay mình được chi bao nhiêu'), contains('400.000 ₫/ngày'));
      p.dispose();
    });

    test('Tìm giao dịch theo danh mục và thời gian trả về danh sách để hiển thị', () {
      final p = FinanceProvider();
      p.saveEntry(spend('pho', 45000, 'food', DateTime(2026, 10, 19), note: 'Phở bò'));
      p.saveEntry(spend('cafe', 30000, 'food', DateTime(2026, 10, 20, 8), note: 'Cà phê'));
      p.saveEntry(spend('old', 50000, 'food', DateTime(2026, 10, 10), note: 'Phở gà'));
      p.saveEntry(spend('gas', 70000, 'transport', DateTime(2026, 10, 20, 9)));
      final assistant = LocalAssistant(p, now: now);
      final week = assistant.reply('Tìm các khoản ăn uống tuần này');
      expect(week.actions.single.type, 'show_transactions');
      expect(week.actions.single.data['ids'], ['cafe', 'pho']);
      expect(week.reply, contains('75.000'));
      expect(assistant.reply('tìm phở tháng này').actions.single.data['ids'], ['pho', 'old']);
      expect(assistant.reply('tìm giao dịch karaoke').actions, isEmpty);
      p.dispose();
    });

    testWidgets('Chat tạo nhắc nhở sau khi người dùng xác nhận', (tester) async {
      final p = FinanceProvider();
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: p, child: MaterialApp(theme: AppTheme.lightTheme, home: const AssistantScreen())));
      expect(find.textContaining('Chào Bạn'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('assistant-input')), 'nhắc tôi nộp tiền nhà ngày 5 hàng tháng');
      await tester.tap(find.byTooltip('Gửi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nộp tiền nhà'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(p.reminders.single.title, 'Nộp tiền nhà');
      expect(p.reminders.single.repeat, ReminderRepeat.monthly);
      expect(find.text('Đã xong'), findsOneWidget);
      await tester.tap(find.byTooltip('Nhắc nhở'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hằng tháng'), findsOneWidget);
      p.dispose();
    });

    test('Câu nhắc nhở thành đề xuất cần xác nhận, không gọi máy chủ', () async {
      final p = FinanceProvider();
      final r = await AiRepository(p).chat([
        {'role': 'user', 'content': 'nhắc tôi đóng học phí cuối tháng'}
      ]);
      expect(r.actions.single.type, 'create_reminder');
      expect(r.actions.single.data['title'], 'Đóng học phí');
      p.dispose();
    });
  });
}
