import 'package:finance_app/features/auth/data/datasources/session_store.dart';

class MemorySessionStore implements SessionStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> clear() async => value = null;
}
