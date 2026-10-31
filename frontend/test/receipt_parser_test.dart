import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/ocr/text_recognizer.dart';
import 'package:finance_app/features/ai/on_device/receipt_parser.dart';

const sample = '''CỬA HÀNG TIỆN LỢI CIRCLE K
Địa chỉ: 12 Lê Lợi, Q1
HÓA ĐƠN BÁN HÀNG
Ngày: 18/10/2026 19:32
Nước suối Lavie 2 x 6.000 12.000
Bánh mì sandwich 25.000
Mì ly Hảo Hảo 9.000
Tạm tính 46.000
Giảm giá 0
TỔNG CỘNG 46.000
Tiền khách đưa 100.000
Tiền thối lại 54.000''';

void main() {
  test('Đọc hóa đơn chuẩn: tổng, ngày, cửa hàng, dòng hàng, kiểm tra chéo', () {
    final r = parseReceipt(sample);
    expect(r.total, 46000);
    expect(r.merchant, contains('CIRCLE K'));
    expect(r.date, DateTime(2026, 10, 18, 19, 32));
    expect(r.items.map((i) => i.amount), [12000, 25000, 9000]);
    expect(r.confidence, greaterThanOrEqualTo(0.8));
    expect(r.checks, contains('tiền khách đưa − tiền thừa'));
  });

  test('Sửa lỗi OCR trong số', () {
    expect(cleanOcrNumbers('TONG: 46. 000'), 'TONG: 46.000');
    expect(cleanOcrNumbers('Tong 1O5.OOO'), 'Tong 105.000');
    expect(cleanOcrNumbers('tổng 46 000đ'), 'tổng 46.000đ');
    expect(cleanOcrNumbers('BOSS 2024'), 'BOSS 2024');
  });

  test('Bỏ phiếu sửa tổng đọc nhầm (454.999 → 454.000)', () {
    final r = parseReceipt('HIGHLANDS COFFEE\nTổng tiền hàng: 454.900đ\nTổng cộng: 454.999đ\n'
        'Tiền khách đưa: 500.000\nTiền thừa: 46.000');
    expect(r.total, 454000);
    expect(r.checks.length, greaterThanOrEqualTo(2));
  });

  test('Không có dòng TỔNG: dùng tiền khách đưa − tiền thừa', () {
    expect(parseReceipt('QUÁN A\nCơm gà 45.000\nTrà đá 5.000\nKhách đưa 100.000\nTiền thừa 50.000').total, 50000);
  });

  test('Từ khóa sai chính tả và số nằm ở dòng sau', () {
    expect(parseReceipt('CIRCLE K\nT0NG C0NG\n46.000\nTien thira: 4.000\nTien khach dua 50.000').total, 46000);
  });

  test('Ngày dạng chữ và ISO', () {
    expect(parseReceipt('A\nNgày 18 tháng 10 năm 2026\nTổng 10.000').date?.day, 18);
    expect(parseReceipt('A\n2026-10-05 08:30\nTổng 10.000').date, DateTime(2026, 10, 5, 8, 30));
  });

  test('Dựng dòng từ khối OCR của ảnh nghiêng', () {
    // Ảnh nghiêng ~3°: số tiền bên phải cao hơn nhãn bên trái nhưng vẫn cùng dòng.
    const a = -0.05;
    final rows = groupRows(const [
      OcrLine('Cảm ơn quý khách! Hẹn gặp lại', 40, 20, 520, 24, angle: a),
      OcrLine('Tổng cộng:', 10, 130, 120, 20, angle: 0),
      OcrLine('154.000', 500, 106, 90, 20, angle: 0),
      OcrLine('Tiền thừa:', 10, 160, 120, 20, angle: 0),
      OcrLine('46.000', 500, 136, 80, 20, angle: 0),
    ]);
    expect(rows, ['Cảm ơn quý khách! Hẹn gặp lại', 'Tổng cộng:  154.000', 'Tiền thừa:  46.000']);
  });
}
