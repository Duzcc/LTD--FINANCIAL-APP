import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/main.dart' as app;
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/ai/presentation/ai_screens.dart';
import 'package:finance_app/features/ai/presentation/receipt_scan_screen.dart';
import 'package:finance_app/features/ai/presentation/smart_search_screen.dart';
import 'package:finance_app/core/ocr/text_recognizer.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'package:finance_app/features/ai/on_device/receipt_parser.dart';
import 'package:path_provider/path_provider.dart';

/// Chạy thử toàn bộ luồng chính trên máy ảo thật, gọi backend thật:
/// đăng ký → nhập nhanh bằng AI → ngân sách → đồng bộ → trợ lý AI (đề xuất + xác nhận)
/// → phân tích của AI service → tìm kiếm ngữ nghĩa.
/// Vẽ một hóa đơn (hơi nghiêng như ảnh chụp) thành tệp PNG để thử OCR thật trên thiết bị.
Future<String> renderReceipt() async {
  const lines = [
    'CIRCLE K', '12 Lê Lợi, Q.1', 'HÓA ĐƠN BÁN HÀNG', 'Ngày: 18/10/2026 19:32', '',
    'Nước suối Aquafina      2 x 6.000      12.000', 'Bánh mì sandwich        1 x 25.000     25.000',
    'Mì ly Hảo Hảo           1 x 9.000       9.000', '',
    'Tổng tiền hàng:                         46.000', 'TỔNG CỘNG:                              46.000',
    'Tiền khách đưa:                        100.000', 'Tiền thừa:                              54.000',
    'Cảm ơn quý khách!',
  ];
  const w = 900.0, lineH = 44.0;
  final h = lineH * (lines.length + 3);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFF7F5F0));
  canvas.translate(w / 2, h / 2);
  canvas.rotate(-1.5 * math.pi / 180);
  canvas.translate(-w / 2, -h / 2);
  for (var i = 0; i < lines.length; i++) {
    final tp = TextPainter(
        text: TextSpan(text: lines[i], style: const TextStyle(color: Color(0xFF222222), fontSize: 26, fontFamily: 'Courier')),
        textDirection: TextDirection.ltr)
      ..layout();
    final x = i < 4 || i == lines.length - 1 ? (w - tp.width) / 2 : 30.0;
    tp.paint(canvas, Offset(x, lineH * (i + 1.5)));
  }
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${(await getTemporaryDirectory()).path}/hoa_don_thu.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20));
    await Future<void>.delayed(Duration(milliseconds: ms));
    await t.pump();
  }

  // Android: chuyển bề mặt sang ảnh để chụp (convertFlutterSurfaceToImage) làm pumpAndSettle không
  // bao giờ dừng trên máy ảo → chỉ chụp ảnh trên iOS, Android vẫn chạy đủ các bước kiểm tra.
  final canShoot = defaultTargetPlatform != TargetPlatform.android;
  Future<void> shot(WidgetTester t, String name) async {
    await settle(t, 300);
    if (canShoot) await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
    final f = last ? find.text(text).last : find.text(text).first;
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 20}) async {
    for (var i = 0; i < seconds * 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
      if (f.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Không thấy: $f');
  }

  testWidgets('Chạy thử ứng dụng với backend', (t) async {
    (await SharedPreferences.getInstance()).clear();
    app.main();
    await settle(t, 1500);

    // 1. Đăng ký tài khoản mới trên backend
    await tapText(t, 'Đăng ký');
    final email = 'demo${DateTime.now().millisecondsSinceEpoch % 100000}@nhom3.vn';
    await t.enterText(find.widgetWithText(TextFormField, 'Họ và tên'), 'Trần Văn Đức');
    await t.enterText(find.byKey(const ValueKey('auth-email')), email);
    await t.enterText(find.byKey(const ValueKey('auth-password')), 'matkhau123');
    await t.enterText(find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'), 'matkhau123');
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(t, '01_dang_ky');
    await tapText(t, 'Tạo tài khoản');
    await waitFor(t, find.byType(MainScreen));
    await shot(t, '02_tong_quan_moi');

    final p = Provider.of<FinanceProvider>(t.element(find.byType(MainScreen)), listen: false);
    expect(p.signedIn, isTrue);

    // 2. Ghi giao dịch bằng câu tự nhiên (AI trên thiết bị)
    Future<void> quick(String text, String name) async {
      await t.tap(find.byKey(const ValueKey('quick-entry-button')));
      await settle(t);
      await t.enterText(find.byKey(const ValueKey('quick-entry')), text);
      await settle(t);
      await shot(t, name);
      await tapText(t, 'Tiếp tục');
      await tapText(t, 'Lưu giao dịch');
      if (find.text('Vẫn lưu').evaluate().isNotEmpty) await tapText(t, 'Vẫn lưu');
      await settle(t, 800);
    }

    await quick('lương tháng 15tr', '03_nhap_nhanh_luong');
    await quick('ăn phở 45k sáng nay', '04_nhap_nhanh_pho');
    await quick('đổ xăng 70.000 hôm nay', '05_nhap_nhanh_xang');
    await quick('cho Minh mượn 500k', '06_nhap_nhanh_cho_vay');
    expect(p.entries.length, 4);

    // 3. Ngân sách tháng
    await tapText(t, 'Ngân sách', last: true);
    await t.tap(find.byTooltip('Sửa mục tiêu tháng'));
    await settle(t);
    await t.enterText(find.byType(TextFormField).last, '6000000');
    await tapText(t, 'Lưu', last: true);
    await shot(t, '07_ngan_sach');

    // 4. Tổng quan sau khi có dữ liệu
    await tapText(t, 'Tổng quan', last: true);
    await shot(t, '08_tong_quan');
    await t.drag(find.byType(ListView).first, const Offset(0, -600));
    await shot(t, '09_tong_quan_phan_tich');
    await tapText(t, 'Sổ nợ');
    await shot(t, '10_so_no');

    // 5. Tài khoản: trạng thái đồng bộ, trợ lý AI
    await tapText(t, 'Tài khoản', last: true);
    await p.syncNow();
    await settle(t, 800);
    await shot(t, '11_tai_khoan_dong_bo');
    expect(p.pendingChanges, 0);
    expect(p.syncError, isNull);
    await tapText(t, 'Hỏi trợ lý tài chính');
    await tapText(t, 'Dự báo chi tiêu cuối tháng');
    // Trả lời đến từ AI service (dự báo) hoặc trợ lý trên thiết bị (dự kiến)
    await waitFor(t, find.textContaining(RegExp('dự kiến|Dự báo cả tháng')));
    await shot(t, '12_tro_ly_ai');

    // 6. Trợ lý đề xuất ghi giao dịch, người dùng xác nhận
    await t.enterText(find.byKey(const ValueKey('assistant-input')), 'ghi giúp trà sữa 35k');
    await t.testTextInput.receiveAction(TextInputAction.send);
    await waitFor(t, find.text('Xác nhận'), seconds: 30);
    await shot(t, '13_tro_ly_de_xuat');
    await tapText(t, 'Xác nhận', last: true);
    await tapText(t, 'Lưu giao dịch');
    if (find.text('Vẫn lưu').evaluate().isNotEmpty) await tapText(t, 'Vẫn lưu');
    await settle(t, 800);
    expect(p.entries.length, 5);
    expect(p.entries.any((e) => e.amount == 35000), isTrue);
    final nav = Navigator.of(t.element(find.byType(MainScreen, skipOffstage: false)));

    // 7. Phân tích thông minh từ AI service (dự báo có khoảng tin cậy, bất thường, gợi ý ngân sách)
    nav.push(MaterialPageRoute<void>(builder: (_) => const InsightsScreen()));
    await waitFor(t, find.textContaining(RegExp('Khoảng 80%|trên thiết bị')), seconds: 30);
    await shot(t, '14_phan_tich_ai');
    nav.pop();
    await settle(t);

    // 8. Tìm kiếm bằng câu tự nhiên
    nav.push(MaterialPageRoute<void>(builder: (_) => const SmartSearchScreen()));
    await settle(t);
    await t.enterText(find.byType(TextField).first, 'phở hôm nay');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(t, find.textContaining('kết quả'), seconds: 30);
    await shot(t, '15_tim_kiem_ai');

    // 9. Đọc hóa đơn bằng OCR thật trên thiết bị (Apple Vision / ML Kit) + phân tích
    final path = await renderReceipt();
    final ocr = await const TextRecognizer().recognize(path);
    expect(ocr, isNotNull, reason: 'thiết bị phải có OCR');
    debugPrint('OCR (${ocr!.engine}):\n${ocr.text}');
    final local = parseReceipt(ocr.text);
    expect(local.total, 46000, reason: 'phân tích trên thiết bị');
    final server = await AiRepository(p).readReceipt(path);
    expect(server.total, 46000, reason: 'OCR thiết bị + phân tích máy chủ');
    expect(server.confidence, greaterThanOrEqualTo(0.8));
    debugPrint('Hóa đơn: ${server.merchant} ${server.total} ${server.date} nguồn=${server.source} tin cậy=${server.confidence}');

    // Màn Quét hóa đơn với văn bản vừa nhận dạng
    nav.push(MaterialPageRoute<void>(builder: (_) => const ReceiptScanScreen()));
    await settle(t);
    await tapText(t, 'Hoặc dán nội dung hóa đơn');
    await t.enterText(find.byKey(const ValueKey('receipt-text')), ocr.text);
    await tapText(t, 'Phân tích văn bản');
    await waitFor(t, find.text('Tạo giao dịch chi'), seconds: 30);
    await shot(t, '16_quet_hoa_don');
    await tapText(t, 'Tạo giao dịch chi');
    await tapText(t, 'Lưu giao dịch');
    if (find.text('Vẫn lưu').evaluate().isNotEmpty) await tapText(t, 'Vẫn lưu');
    await settle(t, 800);
    expect(p.entries.any((e) => e.amount == 46000), isTrue);
  });
}
