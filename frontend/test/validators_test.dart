import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/validation/validators.dart';

void main() {
  test('Họ tên: bắt buộc, 2–50 ký tự, chỉ chữ cái', () {
    expect(validateName('Nguyễn Văn An'), isNull);
    expect(validateName("  Đỗ   Thị O'Neil "), isNull);
    expect(validateName(''), isNotNull);
    expect(validateName('A'), contains('2 ký tự'));
    expect(validateName('a' * 51), contains('50'));
    expect(validateName('An123'), contains('chữ cái'));
  });

  test('Email: định dạng và độ dài', () {
    expect(validateEmail(' An@Test.vn '), isNull);
    expect(validateEmail(''), 'Vui lòng nhập email');
    for (final e in ['sai', 'a@b', 'a..b@test.vn', '.a@test.vn', 'a.@test.vn', 'a b@test.vn']) {
      expect(validateEmail(e), 'Email không hợp lệ', reason: e);
    }
    expect(validateEmail('${'a' * 65}@test.vn'), 'Email quá dài');
    expect(validateLoginEmail('old_user@corp.com'), isNull, reason: 'email cũ vẫn đăng nhập được');
    expect(validateLoginEmail('khongphaiemail'), isNotNull);
  });

  test('Mật khẩu mới: 8–72 byte UTF-8, chữ + số, không khoảng trắng, khác email', () {
    expect(validatePassword('Matkhau1'), isNull);
    expect(validatePassword('Ab1'), contains('8'));
    expect(validatePassword('abcdefgh'), contains('chữ cái và chữ số'));
    expect(validatePassword('12345678'), contains('chữ cái và chữ số'));
    expect(validatePassword('Mat khau1'), contains('khoảng trắng'));
    expect(validatePassword('A1${'a' * 71}'), contains('72'));
    expect(validatePassword('A1${'é' * 36}'), contains('72'));
    expect(validatePassword('abc12345@x.vn', email: 'ABC12345@x.vn'), contains('trùng email'));
    expect(validateLoginPassword('123'), isNull, reason: 'đăng nhập không kiểm độ mạnh');
    expect(validateLoginPassword(''), isNotNull);
  });
}
