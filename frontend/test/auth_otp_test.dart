import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/otp_screen.dart';
import 'helpers/fake_backend.dart';

void main() {
  Future<FinanceProvider> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = FinanceProvider(api: ApiClient(client: FakeBackend().client));
    await tester.pumpWidget(FinanceApp(finance: p));
    expect(find.byType(AuthScreen), findsOneWidget);
    return p;
  }

  testWidgets('Đăng ký báo lỗi ràng buộc dưới từng ô nhập', (tester) async {
    await open(tester);
    await tester.tap(find.text('Đăng ký'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'A1');
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'sai@');
    await tester.enterText(find.byKey(const ValueKey('auth-password')), 'abc');
    await tester.enterText(find.byType(TextFormField).at(3), 'khac');
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Họ tên chỉ gồm chữ cái và khoảng trắng'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    expect(find.byType(OtpScreen), findsNothing);
  });

  testWidgets('Đăng nhập phải nhập OTP gửi về email mới vào ứng dụng',
      (tester) async {
    final p = await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('auth-email')), 'an@test.vn');
    await tester.enterText(
        find.byKey(const ValueKey('auth-password')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(OtpScreen), findsOneWidget);
    expect(p.signedIn, isFalse);
    expect(find.textContaining('an@test.vn'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('otp-code')), '000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('không đúng'), findsOneWidget);
    expect(p.signedIn, isFalse);

    await tester.enterText(
        find.byKey(const ValueKey('otp-code')), FakeBackend.otpCode);
    await tester.pumpAndSettle();
    expect(p.signedIn, isTrue);
    expect(find.byType(MainScreen), findsOneWidget);
  });
}
