import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/banking/vietqr.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';

/// Đọc chuỗi TLV của EMVCo thành bảng id → giá trị.
Map<String, String> tlv(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    final id = s.substring(i, i + 2);
    final len = int.parse(s.substring(i + 2, i + 4));
    out[id] = s.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return out;
}

void main() {
  test('CRC-16/CCITT-FALSE đúng giá trị chuẩn', () {
    expect(crc16('123456789'), '29B1');
  });

  test('VietQR có số tiền: QR động, đúng NAPAS, đúng CRC', () {
    final qr = buildVietQr(
        bin: '970422', account: '0123456789', amount: 150000, content: 'LTDAB23CD Tiền điện');
    final f = tlv(qr);
    expect(f['00'], '01');
    expect(f['01'], '12');
    final merchant = tlv(f['38']!);
    expect(merchant['00'], 'A000000727');
    expect(tlv(merchant['01']!), {'00': '970422', '01': '0123456789'});
    expect(merchant['02'], 'QRIBFTTA');
    expect(f['53'], '704');
    expect(f['54'], '150000');
    expect(f['58'], 'VN');
    expect(tlv(f['62']!)['08'], 'LTDAB23CD TIEN DIEN');
    expect(f['63'], crc16(qr.substring(0, qr.length - 4)));
  });

  test('VietQR không số tiền: QR tĩnh, không có trường 54 và 62', () {
    final f = tlv(buildVietQr(bin: '970436', account: '1017588888'));
    expect(f['01'], '11');
    expect(f.containsKey('54'), isFalse);
    expect(f.containsKey('62'), isFalse);
  });

  test('Nội dung chuyển khoản và tên chủ tài khoản', () {
    expect(transferContent('Trả nợ tháng 10 cho Lan nhé bạn ơi'), hasLength(lessThanOrEqualTo(25)));
    expect(transferContent('Trả nợ'), 'TRA NO');
    expect(holderName('nguyễn văn '), 'NGUYEN VAN ', reason: 'giữ khoảng trắng khi đang gõ');
    expect(holderName('  Đỗ  Thị 1'), 'DO THI ');
    expect(validateBankHolder('NGUYEN VAN AN'), isNull);
    expect(validateBankHolder('Nguyễn An'), isNotNull);
    expect(validateBankAccount('0123 456 789'), isNull);
    expect(validateBankAccount('12'), isNotNull);
    expect(bankByBin('970422')?.code, 'MB');
  });

  test('Ví: liên kết ngân hàng phải đủ thông tin và là ví VND', () {
    final p = FinanceProvider();
    MoneyWallet w({String currency = 'VND', String? holder = 'NGUYEN AN'}) => MoneyWallet(
        id: 'mb', name: 'MB', currency: currency,
        bankBin: '970422', bankAccount: '0123456789', bankHolder: holder);
    expect(() => p.saveWallet(w(holder: null)), throwsArgumentError);
    expect(() => p.saveWallet(w(currency: 'USD')), throwsArgumentError);
    expect(() => p.saveWallet(w(holder: 'nguyen an')), throwsArgumentError);
    p.saveWallet(w());
    final saved = p.findWallet('mb')!;
    expect(saved.hasBank, isTrue);
    expect(MoneyWallet.fromJson(saved.toJson()).bankHolder, 'NGUYEN AN');
    p.dispose();
  });
}
