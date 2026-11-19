import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FinanceLocalDataSource {
  FinanceLocalDataSource(this._storage);
  final SharedPreferences? _storage;

  static const dataKey = 'finance_data_v1';

  bool get persistent => _storage != null;

  Map<String, dynamic>? read() {
    final raw = _storage?.getString(dataKey);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<bool> write(Map<String, dynamic> data) async => await _storage?.setString(dataKey, jsonEncode(data)) ?? true;

  Future<void> clear() async => _storage?.remove(dataKey);
}
