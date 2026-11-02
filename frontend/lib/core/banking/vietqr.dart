/// Tạo chuỗi VietQR (chuẩn EMVCo/NAPAS) để nhận chuyển khoản liên ngân hàng 24/7.
/// Mọi ứng dụng ngân hàng tại Việt Nam đều quét được; tạo ngay trên máy, không cần mạng.
library;

import 'package:finance_app/features/ai/on_device/category_model.dart'
    show foldVietnamese;

class VietBank {
  const VietBank(this.bin, this.code, this.name);
  final String bin, code, name;
}

/// Khớp với backend/src/services/banks.js (mã BIN theo NAPAS).
const vietBanks = [
  VietBank('970436', 'VCB', 'Vietcombank'),
  VietBank('970415', 'ICB', 'VietinBank'),
  VietBank('970418', 'BIDV', 'BIDV'),
  VietBank('970405', 'VBA', 'Agribank'),
  VietBank('970422', 'MB', 'MBBank'),
  VietBank('970407', 'TCB', 'Techcombank'),
  VietBank('970416', 'ACB', 'ACB'),
  VietBank('970432', 'VPB', 'VPBank'),
  VietBank('970423', 'TPB', 'TPBank'),
  VietBank('970403', 'STB', 'Sacombank'),
  VietBank('970437', 'HDB', 'HDBank'),
  VietBank('970441', 'VIB', 'VIB'),
  VietBank('970443', 'SHB', 'SHB'),
  VietBank('970431', 'EIB', 'Eximbank'),
  VietBank('970426', 'MSB', 'MSB'),
  VietBank('970448', 'OCB', 'OCB'),
  VietBank('970440', 'SEAB', 'SeABank'),
  VietBank('970449', 'LPB', 'LPBank'),
  VietBank('970428', 'NAB', 'Nam A Bank'),
  VietBank('546034', 'CAKE', 'CAKE by VPBank'),
  VietBank('963388', 'TIMO', 'Timo'),
];

VietBank? bankByBin(String? bin) {
  for (final b in vietBanks) {
    if (b.bin == bin) return b;
  }
  return null;
}

/// Nội dung chuyển khoản: IN HOA, không dấu, tối đa 25 ký tự (giới hạn của trường mục đích giao dịch).
String transferContent(String text) {
  final s = foldVietnamese(text).toUpperCase();
  return s.length > 25 ? s.substring(0, 25).trim() : s;
}

const _accented = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _plain = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Tên chủ tài khoản theo cách ngân hàng hiển thị: IN HOA, không dấu.
/// Giữ khoảng trắng cuối để người dùng gõ tiếp được từ sau.
String holderName(String text) {
  final b = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = _accented.indexOf(ch);
    b.write(i >= 0 ? _plain[i] : ch);
  }
  return b
      .toString()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z ]'), '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .replaceFirst(RegExp(r'^ +'), '');
}

String _tlv(String id, String value) =>
    '$id${value.length.toString().padLeft(2, '0')}$value';

/// CRC-16/CCITT-FALSE (đa thức 0x1021, giá trị đầu 0xFFFF) theo EMVCo.
String crc16(String data) {
  var crc = 0xFFFF;
  for (final byte in data.codeUnits) {
    crc ^= byte << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Chuỗi QR chuyển khoản tới [account] tại ngân hàng [bin]. Có [amount] → QR động
/// (người chuyển không phải nhập số tiền).
String buildVietQr(
    {required String bin,
    required String account,
    double? amount,
    String? content}) {
  final merchant = _tlv('00', 'A000000727') +
      _tlv('01', _tlv('00', bin) + _tlv('01', account)) +
      _tlv('02', 'QRIBFTTA'); // chuyển nhanh tới tài khoản
  final hasAmount = amount != null && amount > 0;
  final note = content == null ? '' : transferContent(content);
  final body = [
    _tlv('00', '01'),
    _tlv('01', hasAmount ? '12' : '11'),
    _tlv('38', merchant),
    _tlv('53', '704'), // VND
    if (hasAmount) _tlv('54', amount.round().toString()),
    _tlv('58', 'VN'),
    if (note.isNotEmpty) _tlv('62', _tlv('08', note)),
    '6304',
  ].join();
  return body + crc16(body);
}
