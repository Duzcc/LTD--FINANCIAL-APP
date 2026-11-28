import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/app/app_navigator.dart';
import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/features/auth/presentation/screens/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'helpers/fake_backend.dart';
import 'helpers/memory_session_store.dart';

void main() {
  Future<FinanceProvider> open(WidgetTester tester, {FakeBackend? backend}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p =
        FinanceProvider(api: ApiClient(client: (backend ?? FakeBackend()).client), sessionStore: MemorySessionStore());
    await tester.pumpWidget(FinanceApp(finance: p));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    return p;
  }

  testWidgets('Đăng ký chỉ báo lỗi trên ô đang được nhập', (tester) async {
    await open(tester);
    await tester.tap(find.text('Đăng ký'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('auth-password')),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(TextFormField).last,
        matching: find.byIcon(Icons.lock_reset),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(TextFormField).at(0));
    await tester.pumpAndSettle();
    expect(find.text('Họ tên chỉ gồm chữ cái và khoảng trắng'), findsNothing);
    expect(find.text('Email không hợp lệ'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'A1');
    await tester.pumpAndSettle();
    expect(find.text('Họ tên chỉ gồm chữ cái và khoảng trắng'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsNothing);
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsNothing);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'sai@');
    await tester.pumpAndSettle();
    expect(find.text('Họ tên chỉ gồm chữ cái và khoảng trắng'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsNothing);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('auth-password')), 'abc');
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(3), 'khac');
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Họ tên chỉ gồm chữ cái và khoảng trắng'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    expect(find.byType(VerificationPendingScreen), findsNothing);
  });

  testWidgets('Đăng nhập bằng email và mật khẩu vào ứng dụng', (tester) async {
    final p = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'sai@');
    await tester.pumpAndSettle();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'an@test.vn');
    await tester.enterText(find.byKey(const ValueKey('auth-password')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(p.signedIn, isTrue);
    expect(find.byType(MainScreen), findsOneWidget);
  });

  testWidgets('Đăng ký hướng dẫn xác minh email trước khi đăng nhập', (tester) async {
    final p = await open(tester);
    await tester.tap(find.text('Đăng ký'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Nguyễn An');
    await tester.enterText(find.byKey(const ValueKey('auth-email')), 'an@test.vn');
    await tester.enterText(find.byKey(const ValueKey('auth-password')), 'Matkhau1');
    await tester.enterText(find.byType(TextFormField).at(3), 'Matkhau1');
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(find.byType(VerificationPendingScreen), findsOneWidget);
    expect(p.signedIn, isFalse);
    expect(find.textContaining('an@test.vn'), findsOneWidget);
  });

  testWidgets('Quên mật khẩu chỉ gửi liên kết đặt lại qua email', (tester) async {
    await open(tester);
    await tester.tap(find.text('Quên mật khẩu?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'sai@');
    await tester.pumpAndSettle();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    await tester.tap(find.text('Gửi liên kết đặt lại mật khẩu'));
    await tester.pumpAndSettle();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'an@test.vn');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gửi liên kết đặt lại mật khẩu'));
    await tester.pumpAndSettle();
    expect(find.text('Đã gửi liên kết đặt lại mật khẩu. Hãy kiểm tra hộp thư.'), findsOneWidget);
    expect(find.text('Đặt lại mật khẩu'), findsNothing);
  });

  testWidgets('Quên mật khẩu báo rõ khi email chưa được đăng ký', (tester) async {
    final backend = FakeBackend()
      ..forgotPasswordResult = {
        'registered': false,
        'verified': false,
        'mailEnabled': false,
        'message': 'Email này chưa được đăng ký.',
      };
    await open(tester, backend: backend);
    await tester.tap(find.text('Quên mật khẩu?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'chua-dang-ky@test.vn');
    await tester.tap(find.text('Gửi liên kết đặt lại mật khẩu'));
    await tester.pumpAndSettle();
    expect(find.text('Email này chưa được đăng ký.'), findsOneWidget);
    expect(find.text('Liên kết kiểm tra:'), findsNothing);
    expect(find.text('Gửi liên kết đặt lại mật khẩu'), findsOneWidget);
  });

  testWidgets('Đổi mật khẩu chỉ hiện lỗi của các ô đã nhập', (tester) async {
    final p = FinanceProvider(sessionStore: MemorySessionStore());
    await tester
        .pumpWidget(ChangeNotifierProvider.value(value: p, child: const MaterialApp(home: ChangePasswordScreen())));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(TextFormField).at(0), matching: find.byIcon(Icons.lock_outline)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(TextFormField).at(1), matching: find.byIcon(Icons.lock_outline)),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Matkhau1');
    await tester.enterText(find.byType(TextFormField).at(2), 'khac');
    await tester.pumpAndSettle();
    expect(find.text('Nhập mật khẩu hiện tại'), findsNothing);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập mật khẩu hiện tại'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
  });

  testWidgets('Bấm xác nhận trong email mở đăng nhập sau khi xác minh', (tester) async {
    final backend = FakeBackend();
    await open(tester, backend: backend);
    appNavigatorKey.currentState!.pushNamed(AppRoutes.verifyEmail, arguments: 'email-token');
    await tester.pumpAndSettle();
    expect(backend.verifiedEmailToken, 'email-token');
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Email đã được xác minh. Mời bạn đăng nhập.'), findsOneWidget);
  });

  testWidgets('Bấm xác nhận đặt lại mở form và sau đó đưa về đăng nhập', (tester) async {
    final backend = FakeBackend();
    await open(tester, backend: backend);
    appNavigatorKey.currentState!.pushNamed(AppRoutes.resetPassword, arguments: 'reset-token');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-new-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('reset-confirm-password')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reset-new-password')),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reset-confirm-password')),
        matching: find.byIcon(Icons.lock_reset),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('reset-new-password')), 'abc');
    await tester.enterText(find.byKey(const ValueKey('reset-confirm-password')), 'khac');
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu tối thiểu 8 ký tự'), findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('reset-new-password')), 'Moi12345');
    await tester.enterText(find.byKey(const ValueKey('reset-confirm-password')), 'Moi12345');
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(backend.resetRequest?['token'], 'reset-token');
    expect(backend.resetRequest?['newPassword'], 'Moi12345');
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Mật khẩu đã được đặt lại. Hãy đăng nhập bằng mật khẩu mới.'), findsOneWidget);
  });
}
