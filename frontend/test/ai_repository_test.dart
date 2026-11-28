import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/ai/data/repositories/ai_repository.dart';
import 'helpers/fake_backend.dart';
import 'helpers/memory_session_store.dart';

void main() {
  Future<(FinanceProvider, FakeBackend)> signedIn() async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    await signIn(p);
    return (p, server);
  }

  test('Offline: dùng mô hình trên thiết bị, không gọi máy chủ', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client), sessionStore: MemorySessionStore());
    final repo = AiRepository(p);
    final (entry, remote) = await repo.parse('ăn phở 45k');
    expect(remote, isFalse);
    expect(entry.amount, 45000);
    final reply = await repo.chat([
      {'role': 'user', 'content': 'tháng này chi bao nhiêu'}
    ]);
    expect(reply.source, 'device');
    expect(await repo.insights(), isNull);
    expect(server.aiCalls, isEmpty);
    p.dispose();
  });

  test('Nhập nhanh dùng kết quả máy chủ khi tin cậy hơn', () async {
    final (p, server) = await signedIn();
    server.ai['/api/ai/parse'] = (b) => {
          'kind': 'lend',
          'amount': 500000,
          'date': '2026-10-28T03:00:00.000Z',
          'note': 'Cho Minh mượn',
          'newPersonName': 'Minh',
          'walletId': 'cash',
          'confidence': 0.99,
        };
    final (entry, remote) = await AiRepository(p).parse('cho Minh mượn 500k');
    expect(remote, isTrue);
    expect(entry.kind, EntryKind.lend);
    expect(entry.newPersonName, 'Minh');
    expect(entry.walletId, 'cash');
    p.dispose();
  });

  test('Máy chủ lỗi: tự lùi về thiết bị', () async {
    final (p, server) = await signedIn();
    final (entry, remote) = await AiRepository(p).parse('đổ xăng 70k');
    expect(remote, isFalse);
    expect(entry.amount, 70000);
    expect(server.aiCalls, ['/api/ai/parse']);
    p.dispose();
  });

  test('Trợ lý máy chủ trả hành động cần xác nhận; đẩy thay đổi trước khi hỏi', () async {
    final (p, server) = await signedIn();
    p.saveEntry(MoneyEntry(
        id: 'e1',
        kind: EntryKind.expense,
        amount: 30000,
        walletId: 'cash',
        categoryId: 'food',
        date: DateTime(2026, 10, 5)));
    server.ai['/api/ai/chat'] = (b) => {
          'reply': 'Mình đã chuẩn bị giao dịch.',
          'source': 'ai-service',
          'actions': [
            {
              'type': 'create_transaction',
              'data': {'kind': 'expense', 'amount': 35000, 'categoryId': 'food'}
            }
          ],
        };
    final r = await AiRepository(p).chat([
      {'role': 'user', 'content': 'ghi cà phê 35k'}
    ]);
    expect(r.source, 'ai-service');
    expect(r.actions.single.data['amount'], 35000);
    expect(server.batches, isNotEmpty, reason: 'thay đổi cục bộ phải được đẩy lên trước');
    expect(p.pendingChanges, 0);
    p.dispose();
  });

  test('Phân tích máy chủ: dự báo, bất thường, gợi ý ngân sách', () async {
    final (p, server) = await signedIn();
    server.ai['/api/ai/insights'] = (_) => {
          'forecast': {
            'spent': 100,
            'projected': 300,
            'lower': 250,
            'upper': 380,
            'daysLeft': 10,
            'method': 'weekday_profile',
            'nextMonth': 320
          },
          'anomalies': {
            'anomalies': [
              {
                'transactionId': 'e1',
                'score': 0.9,
                'kind': 'amount',
                'reasons': ['Cao gấp 5 lần']
              }
            ],
            'spikes': []
          },
          'budgets': {
            'suggestions': [
              {'categoryId': 'food', 'amount': 3000000, 'group': 'needs', 'note': 'Trung vị'}
            ],
            'plan': null
          },
        };
    final s = (await AiRepository(p).insights())!;
    expect(s.forecast!.projected, 300);
    expect(s.forecast!.upper, 380);
    expect(s.anomalies.single.reasons.single, 'Cao gấp 5 lần');
    expect(s.budgets.single.amount, 3000000);
    p.dispose();
  });

  test('Nhiều yêu cầu cùng gặp 401 chỉ làm mới token một lần', () async {
    final (p, server) = await signedIn();
    server.ai['/api/ai/chat'] = (_) => {'reply': 'Chào', 'source': 'ai-service', 'actions': []};
    server.token = 'tok2';
    final history = [
      {'role': 'user', 'content': 'chào'}
    ];
    final replies = await Future.wait([AiRepository(p).chat(history), AiRepository(p).chat(history)]);
    expect(replies.map((r) => r.source), ['ai-service', 'ai-service']);
    expect(server.refreshCalls, 1);
    expect(p.session!.token, 'tok2');
    p.dispose();
  });

  test('Phân tích máy chủ: dữ liệu đổi trong lúc chờ thì không coi kết quả là mới; lỗi thì chờ trước khi thử lại',
      () async {
    final (p, server) = await signedIn();
    final repo = AiRepository(p);
    server.ai['/api/ai/insights'] = (_) {
      p.saveEntry(MoneyEntry(
          id: 'e9', kind: EntryKind.expense, amount: 1, walletId: 'cash', categoryId: 'food', date: DateTime.now()));
      return {
        'forecast': {'spent': 1, 'projected': 2, 'lower': 1, 'upper': 3, 'daysLeft': 1, 'method': 'x'}
      };
    };
    expect(await repo.insights(), isNotNull);
    expect(repo.cachedInsights, isNull, reason: 'kết quả được tính trước khi có giao dịch mới');

    server.ai.remove('/api/ai/insights');
    await repo.insights();
    final calls = server.aiCalls.length;
    repo.refreshInsightsIfStale();
    await Future<void>.delayed(Duration.zero);
    expect(server.aiCalls.length, calls, reason: 'vừa lỗi thì không gọi lại ngay');
    p.dispose();
  });

  test('Nhiều thay đổi liền nhau chỉ gọi phân tích một lần; đồng bộ xong vẫn giữ kết quả', () async {
    final (p, server) = await signedIn();
    final repo = AiRepository(p);
    server.ai['/api/ai/insights'] = (_) => {
          'forecast': {'spent': 1, 'projected': 2, 'lower': 1, 'upper': 3, 'daysLeft': 1, 'method': 'x'}
        };
    for (var i = 0; i < 3; i++) {
      p.saveEntry(MoneyEntry(
          id: 'burst$i',
          kind: EntryKind.expense,
          amount: 1000,
          walletId: 'cash',
          categoryId: 'food',
          date: DateTime.now()));
      repo.refreshInsightsIfStale();
    }
    expect(server.aiCalls.where((c) => c.endsWith('/insights')), isEmpty, reason: 'chưa đẩy lên máy chủ thì chưa hỏi');
    await p.syncNow(pull: false);
    repo.refreshInsightsIfStale();
    repo.refreshInsightsIfStale();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.aiCalls.where((c) => c.endsWith('/insights')).length, 1);
    expect(repo.cachedInsights, isNotNull);
    await p.syncNow(pull: false);
    expect(repo.cachedInsights, isNotNull, reason: 'đồng bộ không đổi dữ liệu thì kết quả vẫn mới');
    p.dispose();
  });

  test('Đọc hóa đơn từ văn bản', () async {
    final (p, server) = await signedIn();
    server.ai['/api/ai/receipts/text'] = (b) => {
          'merchant': 'Circle K',
          'total': 46000,
          'date': '2026-10-18T00:00:00',
          'note': 'Circle K: Nước suối',
          'items': [
            {'name': 'Nước suối', 'amount': 12000}
          ],
          'source': 'text',
        };
    final r = await AiRepository(p).receiptFromText('TỔNG CỘNG 46.000');
    expect(r.total, 46000);
    expect(r.items.single.name, 'Nước suối');
    p.dispose();
  });
}
