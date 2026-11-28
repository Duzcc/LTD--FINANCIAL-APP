import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';
import 'helpers/memory_session_store.dart';

void main() {
  test('Sai mật khẩu thì hiện đúng thông báo lỗi', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    await expectLater(p.signIn(email: 'an@test.vn', password: 'sai'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('không đúng'))));
    p.dispose();
  });

  test('Đăng nhập tạo phiên và tải dữ liệu tài khoản', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    await p.signIn(email: ' AN@test.vn ', password: '123456');
    expect(p.signedIn, isTrue);
    p.dispose();
  });

  test('Đăng nhập, gửi thay đổi trên máy theo đúng thứ tự rồi đăng xuất', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final server = FakeBackend();
    final sessionStore = MemorySessionStore();
    final p = FinanceProvider(storage: storage, api: ApiClient(client: server.client), sessionStore: sessionStore);
    expect(await signIn(p), isFalse);
    expect(p.signedIn, isTrue);
    expect(p.displayName, 'An');

    p.saveWallet(const MoneyWallet(id: 'bank', name: 'Ngân hàng', opening: 100));
    p.saveEntry(MoneyEntry(
        id: 'e1',
        kind: EntryKind.expense,
        amount: 30,
        walletId: 'bank',
        categoryId: 'food',
        date: DateTime(2026, 10, 5, 9)));
    expect(p.pendingChanges, 2);
    await p.syncNow(pull: false);
    expect(p.pendingChanges, 0);
    expect(p.syncError, isNull);
    final ops = server.batches.last['ops'] as List;
    expect(ops.map((o) => '${o['entity']}:${o['id']}'), ['wallets:bank', 'entries:e1']);
    expect((ops[1]['data'] as Map)['date'], endsWith('Z'));

    p.deleteEntry('e1');
    p.deleteWallet('bank');
    await p.syncNow();
    final deletes = server.batches.last['ops'] as List;
    expect(deletes.map((o) => '${o['action']} ${o['entity']}'), ['delete entries', 'delete wallets']);
    expect(p.wallets.map((w) => w.id), ['cash']);

    await p.flush();
    expect(storage.getString(FinanceProvider.storageKey), isNot(contains('refreshToken')));
    expect(storage.getString(FinanceProvider.storageKey), isNot(contains('"token":"tok"')));
    final again = FinanceProvider(storage: storage, api: ApiClient(client: server.client), sessionStore: sessionStore);
    await again.restore();
    expect(again.session?.token, 'tok');
    again.dispose();

    await p.signOut();
    expect(p.signedIn, isFalse);
    expect(storage.containsKey(FinanceProvider.storageKey), isFalse);
    expect(server.requests.last.url.path, '/api/auth/logout');
    p.dispose();
  });

  test('Chuyển token cũ khỏi SharedPreferences sang kho phiên bảo mật', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final p = FinanceProvider(storage: storage);
    p.preferences(name: 'An');
    await p.flush();
    final saved = jsonDecode(storage.getString(FinanceProvider.storageKey)!) as Map<String, dynamic>;
    saved['session'] = const AccountSession(
      baseUrl: 'http://localhost:3000',
      token: 'legacy-access',
      refreshToken: 'legacy-refresh',
      email: 'an@test.vn',
      userId: 'user-1',
    ).toJson();
    await storage.setString(FinanceProvider.storageKey, jsonEncode(saved));

    final sessionStore = MemorySessionStore();
    final restored = FinanceProvider(storage: storage, sessionStore: sessionStore);
    await restored.restore();

    expect(restored.session?.token, 'legacy-access');
    expect(sessionStore.value, contains('legacy-refresh'));
    final migrated = jsonDecode(storage.getString(FinanceProvider.storageKey)!) as Map<String, dynamic>;
    expect(migrated.containsKey('session'), isFalse);
    p.dispose();
    restored.dispose();
  });

  test('Có dữ liệu trên máy thì hỏi trước khi thay bằng dữ liệu tài khoản', () async {
    final server = FakeBackend();
    (server.snapshot['entries'] as List).add({
      'id': 'remote',
      'kind': 'income',
      'amount': 500,
      'walletId': 'cash',
      'categoryId': 'salary',
      'date': '2026-10-01T02:00:00.000Z'
    });
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    p.saveEntry(MoneyEntry(
        id: 'local',
        kind: EntryKind.expense,
        amount: 20,
        walletId: 'cash',
        categoryId: 'food',
        date: DateTime(2026, 10, 2)));
    expect(await signIn(p), isTrue);
    expect(p.needsLoginDecision, isTrue);
    await p.resolveLogin(useAccount: false);
    expect(p.entries.map((e) => e.id).toSet(), {'local', 'remote'});
    expect(p.balance('cash'), 480);
    p.dispose();
  });

  test('Hết phiên thì báo lỗi mà không mất thay đổi đang chờ', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    await signIn(p);
    p.session = p.session!.withToken('expired', refresh: 'revoked');
    p.preferences(name: 'Bình');
    await p.syncNow();
    expect(p.syncError, contains('hết hạn'));
    expect(p.pendingChanges, 1);
    p.dispose();
  });

  test('Ô số tiền định dạng phần nghìn kiểu Việt Nam', () {
    final f = AmountInputFormatter();
    expect(f.formatEditUpdate(const TextEditingValue(text: '125000'), const TextEditingValue(text: '1250000')).text,
        '1.250.000');
    expect(f.formatEditUpdate(const TextEditingValue(text: '12'), const TextEditingValue(text: '12.')).text, '12,');
    expect(parseAmount('1.250.000'), 1250000);
    expect(parseAmount('12,5'), 12.5);
    expect(formatAmountInput(1250000), '1.250.000');
    expect(formatAmountInput(12.5), '12,5');
  });
}
