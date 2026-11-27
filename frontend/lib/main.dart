import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/features/security/data/services/app_lock.dart';
import 'package:finance_app/core/services/notification_service.dart';

// không mở được bộ nhớ thì app vẫn chạy, chỉ là không lưu được
Future<SharedPreferences?> _openStorage() async {
  try {
    return await SharedPreferences.getInstance();
  } on Exception {
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark));
  final storage = await _openStorage();
  final finance = FinanceProvider(storage: storage)..restore();
  if (storage == null) {
    finance.storageError = 'Không mở được bộ nhớ thiết bị. Dữ liệu hiện chỉ lưu trong phiên sử dụng này.';
  }
  finance.onScheduleChanged = NotificationService.instance.apply;
  finance.onWalletActivity = NotificationService.instance.walletActivity;
  finance.onBudgetExceeded = NotificationService.instance.budgetExceeded;
  finance.runRecurring();
  runApp(FinanceApp(
      finance: finance,
      lock: AppLock(storage: storage),
      returning: storage?.containsKey(FinanceProvider.storageKey) ?? false));
  unawaited(NotificationService.instance.apply(finance));
  if (finance.signedIn) unawaited(finance.syncNow());
}
