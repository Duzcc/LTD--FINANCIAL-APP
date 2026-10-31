import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

void main() {
  test('Login with wrong password reports the server message', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client));
    await expectLater(
        p.signIn(email: 'an@test.vn', password: 'sai'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('không đúng'))));
    p.dispose();
  });

  test('Login, push local changes in dependency order, then logout',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final server = FakeBackend();
    final p = FinanceProvider(
        storage: storage, api: ApiClient(client: server.client));
    expect(await p.signIn(email: 'an@test.vn', password: '123456'), isFalse);
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
    expect(ops.map((o) => '${o['entity']}:${o['id']}'),
        ['wallets:bank', 'entries:e1']);
    // Thời điểm gửi lên luôn kèm múi giờ để máy chủ không hiểu sai ngày.
    expect((ops[1]['data'] as Map)['date'], endsWith('Z'));

    p.deleteEntry('e1');
    p.deleteWallet('bank');
    await p.syncNow();
    final deletes = server.batches.last['ops'] as List;
    expect(deletes.map((o) => '${o['action']} ${o['entity']}'),
        ['delete entries', 'delete wallets']);
    expect(p.wallets.map((w) => w.id), ['cash']);

    // Phiên được lưu và khôi phục sau khi mở lại ứng dụng.
    await p.flush();
    final again = FinanceProvider(
        storage: storage, api: ApiClient(client: server.client))
      ..restore();
    expect(again.session?.token, 'tok');
    again.dispose();

    await p.signOut();
    expect(p.signedIn, isFalse);
    expect(storage.containsKey(FinanceProvider.storageKey), isFalse);
    expect(server.requests.last.url.path, '/api/auth/logout');
    p.dispose();
  });

  test('Existing local data asks before replacing account data', () async {
    final server = FakeBackend();
    (server.snapshot['entries'] as List).add({
      'id': 'remote',
      'kind': 'income',
      'amount': 500,
      'walletId': 'cash',
      'categoryId': 'salary',
      'date': '2026-10-01T02:00:00.000Z'
    });
    final p = FinanceProvider(api: ApiClient(client: server.client));
    p.saveEntry(MoneyEntry(
        id: 'local',
        kind: EntryKind.expense,
        amount: 20,
        walletId: 'cash',
        categoryId: 'food',
        date: DateTime(2026, 10, 2)));
    expect(await p.signIn(email: 'an@test.vn', password: '123456'), isTrue);
    expect(p.needsLoginDecision, isTrue);
    await p.resolveLogin(useAccount: false);
    expect(p.entries.map((e) => e.id).toSet(), {'local', 'remote'});
    expect(p.balance('cash'), 480);
    p.dispose();
  });

  test('Expired session is reported without losing pending changes',
      () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client));
    await p.signIn(email: 'an@test.vn', password: '123456');
    p.session = p.session!.withToken('expired');
    p.preferences(name: 'Bình');
    await p.syncNow();
    expect(p.syncError, contains('hết hạn'));
    expect(p.pendingChanges, 1);
    p.dispose();
  });

  test('Amount input helpers format Vietnamese thousands', () {
    final f = AmountInputFormatter();
    expect(
        f
            .formatEditUpdate(const TextEditingValue(text: '125000'),
                const TextEditingValue(text: '1250000'))
            .text,
        '1.250.000');
    expect(
        f
            .formatEditUpdate(const TextEditingValue(text: '12'),
                const TextEditingValue(text: '12.'))
            .text,
        '12,');
    expect(parseAmount('1.250.000'), 1250000);
    expect(parseAmount('12,5'), 12.5);
    expect(formatAmountInput(1250000), '1.250.000');
    expect(formatAmountInput(12.5), '12,5');
  });
}
