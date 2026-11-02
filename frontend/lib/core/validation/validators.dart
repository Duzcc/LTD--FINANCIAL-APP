/// Ràng buộc dữ liệu tài khoản, đồng bộ với backend (backend/src/routes/auth.js).
/// Mỗi hàm trả về null khi hợp lệ, ngược lại là thông báo lỗi để hiện dưới ô nhập.
library;

final _emailPattern =
    RegExp(r'^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$');
final _namePattern = RegExp(r"^\p{L}[\p{L} .'-]*$", unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);
final _digit = RegExp(r'\d');
final _space = RegExp(r'\s');
final _otpPattern = RegExp(r'^\d{6}$');

/// Họ tên: 2–50 ký tự, chỉ gồm chữ cái (có dấu), khoảng trắng và . ' -
String? validateName(String? v) {
  final n = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty) return 'Vui lòng nhập họ tên';
  if (n.length < 2) return 'Họ tên phải có ít nhất 2 ký tự';
  if (n.length > 50) return 'Họ tên tối đa 50 ký tự';
  if (!_namePattern.hasMatch(n)) return 'Họ tên chỉ gồm chữ cái và khoảng trắng';
  return null;
}

String? validateEmail(String? v) {
  final e = (v ?? '').trim().toLowerCase();
  if (e.isEmpty) return 'Vui lòng nhập email';
  if (e.length > 254 || e.split('@').first.length > 64) return 'Email quá dài';
  if (!_emailPattern.hasMatch(e) ||
      e.contains('..') ||
      e.startsWith('.') ||
      e.contains('.@')) {
    return 'Email không hợp lệ';
  }
  return null;
}

/// Mật khẩu khi đăng nhập: chỉ bắt buộc nhập (tài khoản cũ có thể đặt mật khẩu theo quy tắc trước).
String? validateLoginPassword(String? v) =>
    (v ?? '').isEmpty ? 'Vui lòng nhập mật khẩu' : null;

/// Mật khẩu mới (đăng ký, đặt lại, đổi mật khẩu): 8–72 ký tự, có cả chữ và số,
/// không chứa khoảng trắng, không trùng email.
String? validatePassword(String? v, {String? email}) {
  final p = v ?? '';
  if (p.isEmpty) return 'Vui lòng nhập mật khẩu';
  if (p.length < 8) return 'Mật khẩu tối thiểu 8 ký tự';
  if (p.length > 72) return 'Mật khẩu tối đa 72 ký tự';
  if (_space.hasMatch(p)) return 'Mật khẩu không được chứa khoảng trắng';
  if (!_letter.hasMatch(p) || !_digit.hasMatch(p)) {
    return 'Mật khẩu phải có cả chữ cái và chữ số';
  }
  if (email != null && p.toLowerCase() == email.trim().toLowerCase()) {
    return 'Mật khẩu không được trùng email';
  }
  return null;
}

const passwordRules = 'Ít nhất 8 ký tự, gồm cả chữ cái và chữ số';

String? validateOtp(String? v) =>
    _otpPattern.hasMatch((v ?? '').trim()) ? null : 'Mã OTP gồm đúng 6 chữ số';

/// Số tài khoản ngân hàng: 6–19 chữ số hoặc chữ cái (bỏ khoảng trắng).
String? validateBankAccount(String? v) {
  final a = (v ?? '').replaceAll(RegExp(r'\s+'), '');
  if (a.isEmpty) return 'Vui lòng nhập số tài khoản';
  if (!RegExp(r'^[A-Za-z0-9]{6,19}$').hasMatch(a)) {
    return 'Số tài khoản gồm 6–19 chữ số hoặc chữ cái';
  }
  return null;
}

/// Tên chủ tài khoản: IN HOA không dấu như trên thẻ/ứng dụng ngân hàng, 2–50 ký tự.
String? validateBankHolder(String? v) {
  final n = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty) return 'Vui lòng nhập tên chủ tài khoản';
  if (!RegExp(r'^[A-Z ]{2,50}$').hasMatch(n)) {
    return 'Viết IN HOA không dấu, 2–50 ký tự (VD: NGUYEN VAN AN)';
  }
  return null;
}
