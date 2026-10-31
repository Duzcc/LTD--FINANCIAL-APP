import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Khóa ứng dụng bằng mã PIN 4–6 số. Mã PIN chỉ lưu trên thiết bị dưới dạng
/// SHA-256 có muối (salt), không bao giờ lưu dạng gốc và không đồng bộ lên máy chủ.
class AppLock extends ChangeNotifier {
  AppLock({SharedPreferences? storage}) : _storage = storage {
    _stored = storage?.getString(key);
    locked = enabled;
  }
  static const key = 'finance_pin_v1';
  static const maxAttempts = 5;
  final SharedPreferences? _storage;
  String? _stored;
  bool locked = false;
  int failed = 0;
  DateTime? blockedUntil;

  /// Khóa lại khi ứng dụng ở nền lâu hơn khoảng này.
  Duration relockAfter = const Duration(seconds: 30);

  bool get enabled => _stored != null;

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool validPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('Mã PIN gồm 4 đến 6 chữ số.');
    final random = Random.secure();
    final salt = base64Url.encode(List.generate(16, (_) => random.nextInt(256)));
    _stored = '$salt:${_hash(salt, pin)}';
    await _storage?.setString(key, _stored!);
    locked = false;
    failed = 0;
    notifyListeners();
  }

  bool check(String pin) {
    final stored = _stored;
    if (stored == null) return true;
    final i = stored.indexOf(':');
    return _hash(stored.substring(0, i), pin) == stored.substring(i + 1);
  }

  /// Mở khóa; trả về thông báo lỗi hoặc null nếu đúng.
  String? unlock(String pin, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (blockedUntil != null && t.isBefore(blockedUntil!)) {
      return 'Thử lại sau ${blockedUntil!.difference(t).inSeconds + 1} giây.';
    }
    if (check(pin)) {
      locked = false;
      failed = 0;
      blockedUntil = null;
      notifyListeners();
      return null;
    }
    failed++;
    if (failed >= maxAttempts) {
      failed = 0;
      blockedUntil = t.add(const Duration(seconds: 30));
      notifyListeners();
      return 'Sai quá $maxAttempts lần. Vui lòng đợi 30 giây.';
    }
    notifyListeners();
    return 'Mã PIN không đúng (còn ${maxAttempts - failed} lần thử).';
  }

  Future<void> disable() async {
    _stored = null;
    locked = false;
    await _storage?.remove(key);
    notifyListeners();
  }

  void lock() {
    if (!enabled || locked) return;
    locked = true;
    notifyListeners();
  }
}
