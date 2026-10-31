import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/ai/data/ai_repository.dart';
import 'helpers/fake_backend.dart';

void main() {
  Future<(FinanceProvider, FakeBackend)> signedIn() async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client));
    await p.signIn(email: 'an@test.vn', password: '123456');
    return (p, server);
  }

  test('Offline: dùng mô hình trên thiết bị, không gọi máy chủ', () async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client));
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
        id: 'e1', kind: EntryKind.expense, amount: 30000, walletId: 'cash', categoryId: 'food', date: DateTime(2026, 10, 5)));
    server.ai['/api/ai/chat'] = (b) => {
          'reply': 'Mình đã chuẩn bị giao dịch.',
          'source': 'ai-service',
          'actions': [
            {'type': 'create_transaction', 'data': {'kind': 'expense', 'amount': 35000, 'categoryId': 'food'}}
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
          'forecast': {'spent': 100, 'projected': 300, 'lower': 250, 'upper': 380, 'daysLeft': 10, 'method': 'weekday_profile', 'nextMonth': 320},
          'anomalies': {
            'anomalies': [
              {'transactionId': 'e1', 'score': 0.9, 'kind': 'amount', 'reasons': ['Cao gấp 5 lần']}
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
    expect(r.items.single.$1, 'Nước suối');
    p.dispose();
  });
}
