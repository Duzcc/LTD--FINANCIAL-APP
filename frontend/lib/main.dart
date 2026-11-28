import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
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
  await storage?.remove('finance_pin_v1');
  final finance = FinanceProvider(storage: storage);
  await finance.restore();
  if (storage == null && finance.storageError == null) {
    finance.storageError = 'Không mở được bộ nhớ thiết bị. Dữ liệu hiện chỉ lưu trong phiên sử dụng này.';
  }
  finance.onScheduleChanged = NotificationService.instance.apply;
  finance.onWalletActivity = NotificationService.instance.walletActivity;
  runApp(FinanceApp(finance: finance, returning: storage?.containsKey(FinanceProvider.storageKey) ?? false));
  unawaited(NotificationService.instance.apply(finance));
  if (finance.signedIn) unawaited(finance.syncNow());
}
