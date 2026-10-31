import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:finance_app/app/main_screen.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/core/theme/app_theme.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/features/auth/presentation/auth_screen.dart';
import 'package:finance_app/features/security/presentation/lock_screen.dart';

/// Gốc ứng dụng: cung cấp state (Provider), theme và cổng khóa ứng dụng.
class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, this.finance, this.lock, this.returning = false});
  final FinanceProvider? finance;
  final AppLock? lock;
  final bool returning;
  @override
  Widget build(BuildContext context) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => finance ?? FinanceProvider()),
        ChangeNotifierProvider(create: (_) => lock ?? AppLock()),
      ],
      child: MaterialApp(
        title: 'Quản lý chi tiêu',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        builder: (context, child) => LockGate(child: child ?? const SizedBox()),
        home: returning ? const MainScreen() : const AuthScreen(),
      ));
}
