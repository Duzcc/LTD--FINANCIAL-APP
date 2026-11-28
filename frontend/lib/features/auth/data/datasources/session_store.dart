import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'finance_app_session_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
