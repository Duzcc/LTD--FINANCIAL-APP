import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/features/banking/presentation/receive_qr_screen.dart';
import 'helpers/fake_backend.dart';

const _mb = MoneyWallet(
    id: 'mb',
    name: 'MB',
    bankBin: '970422',
    bankAccount: '0123456789',
    bankHolder: 'NGUYEN AN');

Future<void> _open(WidgetTester tester, FinanceProvider p, Widget page) async {
  tester.view.physicalSize = const Size(430, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: p, child: MaterialApp(theme: AppTheme.lightTheme, home: page)));
}

void main() {
  testWidgets('Ngoại tuyến: vẫn tạo được mã VietQR, ràng buộc số tiền', (tester) async {
    final p = FinanceProvider()..saveWallet(_mb);
    await _open(tester, p, const ReceiveQrScreen(walletId: 'mb'));
    await tester.enterText(find.byKey(const ValueKey('qr-amount')), '0');
    await tester.tap(find.text('Tạo mã QR'));
    await tester.pump();
    expect(find.text('Nhập số tiền lớn hơn 0'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('qr-amount')), '50000');
    await tester.tap(find.text('Tạo mã QR'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('0123456789'), findsOneWidget);
    expect(find.textContaining('ngoại tuyến'), findsOneWidget);
  });

  testWidgets('Thu nợ: không cho vượt số còn phải thu', (tester) async {
    final p = FinanceProvider()
      ..saveWallet(_mb)
      ..savePerson(const MoneyPerson('lan', 'Lan', 'Bạn bè'))
      ..saveEntry(MoneyEntry(
          id: 'l1', kind: EntryKind.lend, amount: 100000, walletId: 'mb',
          personId: 'lan', date: DateTime(2026, 10, 1)));
    await _open(tester, p,
        const ReceiveQrScreen(walletId: 'mb', personId: 'lan', amount: 100000));
    await tester.enterText(find.byKey(const ValueKey('qr-amount')), '200000');
    await tester.tap(find.text('Tạo mã QR'));
    await tester.pump();
    expect(find.textContaining('Vượt số còn phải thu'), findsOneWidget);
  });

  testWidgets('Đăng nhập: tạo yêu cầu đối soát và tự cập nhật khi tiền về', (tester) async {
    final server = FakeBackend();
    final p = FinanceProvider(api: ApiClient(client: server.client));
    await tester.runAsync(() => signInWithOtp(p));
    p.saveWallet(_mb);
    await _open(tester, p, const ReceiveQrScreen(walletId: 'mb'));
    await tester.enterText(find.byKey(const ValueKey('qr-amount')), '150000');
    await tester.tap(find.text('Tạo mã QR'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('LTDAB23CD'), findsWidgets);
    expect(server.bankRequest!['amount'], 150000);
    expect(find.textContaining('Đang chờ tiền về'), findsOneWidget);

    server.bankRequest!['status'] = 'paid';
    server.bankRequest!['paidAmount'] = 150000;
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Đã nhận'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    p.dispose();
  });
}
