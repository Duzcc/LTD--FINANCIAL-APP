import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/app/app.dart';
import 'package:finance_app/data/finance_provider.dart';
import 'package:finance_app/core/security/app_lock.dart';
import 'package:finance_app/core/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark));
  SharedPreferences? storage;
  try {
    storage = await SharedPreferences.getInstance();
  } catch (_) {/* Show an explicit storage warning below. */}
  final finance = FinanceProvider(storage: storage)..restore();
  if (storage == null) {
    finance.storageError =
        'Không mở được bộ nhớ thiết bị. Dữ liệu hiện chỉ lưu trong phiên sử dụng này.';
  }
  // Thông báo nhắc nhở được lên lịch lại mỗi khi dữ liệu hoặc cài đặt thay đổi.
  finance.onScheduleChanged = NotificationService.instance.apply;
  finance.runRecurring();
  runApp(FinanceApp(
      finance: finance,
      lock: AppLock(storage: storage),
      returning: storage?.containsKey(FinanceProvider.storageKey) ?? false));
  unawaited(NotificationService.instance.apply(finance));
  // Đã đăng nhập: gửi thay đổi đang chờ và tải dữ liệu mới nhất từ backend.
  if (finance.signedIn) unawaited(finance.syncNow());
}
