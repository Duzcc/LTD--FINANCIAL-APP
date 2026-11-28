import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/app/app_routes.dart';
import 'package:finance_app/app/app_navigator.dart';
import 'package:finance_app/app/auth_link_handler.dart';
import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/app/splash_screen.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/auth/presentation/screens/auth_screen.dart';
import 'package:finance_app/features/auth/presentation/screens/email_link_screens.dart';

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, this.finance, this.returning = false});
  final FinanceProvider? finance;
  final bool returning;
  @override
  Widget build(BuildContext context) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => finance ?? FinanceProvider()),
          ],
          child: AuthLinkHandler(
            child: MaterialApp(
              title: 'Quản lý chi tiêu',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              navigatorKey: appNavigatorKey,
              builder: (context, child) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: child ?? const SizedBox()),
              initialRoute: AppRoutes.splash,
              routes: {
                AppRoutes.splash: (_) => SplashScreen(returning: returning),
                AppRoutes.login: (context) => AuthScreen(
                      successMessage: ModalRoute.of(context)?.settings.arguments as String?,
                    ),
                AppRoutes.home: (_) => const MainScreen(),
                AppRoutes.verifyEmail: (context) => VerifyEmailScreen(
                      token: ModalRoute.of(context)!.settings.arguments as String,
                    ),
                AppRoutes.resetPassword: (context) => ResetPasswordScreen(
                      token: ModalRoute.of(context)!.settings.arguments as String,
                    ),
              },
            ),
          ));
}
