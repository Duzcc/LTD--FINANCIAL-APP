import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/finance_provider.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _dailyBase = 100, _debtBase = 1000, _customBase = 2000;
  static const _details = NotificationDetails(
      android: AndroidNotificationDetails('reminders', 'Nhắc nhở',
          channelDescription: 'Nhắc ghi chép thu chi và hạn trả nợ',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority),
      iOS: DarwinNotificationDetails());

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    final offset = DateTime.now().timeZoneOffset;
    tz.setLocalLocation(offset == const Duration(hours: 7)
        ? tz.getLocation('Asia/Ho_Chi_Minh')
        : tz.UTC);
    await _plugin.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false)));
    _ready = true;
  }

  // Máy không hỗ trợ thông báo thì coi như chưa được cho phép; nhắc nhở vẫn được lưu lại.
  Future<bool> requestPermission() => _requestPermission().catchError((Object _) => false);

  Future<bool> _requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  tz.TZDateTime _at(DateTime local) => tz.TZDateTime.from(local, tz.local);

  Future<void> apply(FinanceProvider p) async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    if (p.remindersEnabled) {
      for (final (i, minutes) in p.reminderMinutes.indexed) {
        var at = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
        if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
            id: _dailyBase + i,
            title: 'Đừng quên ghi chép',
            body: 'Dành một phút ghi lại các khoản thu chi hôm nay nhé.',
            scheduledDate: _at(at),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time);
      }
    }
    for (final (i, r) in p.reminders.where((r) => !r.expired(now)).take(50).indexed) {
      await _plugin.zonedSchedule(
          id: _customBase + i,
          title: 'Nhắc nhở chi tiêu',
          body: r.title,
          scheduledDate: _at(r.nextAfter(now)),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: switch (r.repeat) {
            ReminderRepeat.daily => DateTimeComponents.time,
            ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
            ReminderRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
            ReminderRepeat.none => null,
          });
    }
    if (p.debtReminders) {
      var id = _debtBase;
      for (final e in p.entries.where((e) =>
          (e.kind == EntryKind.lend || e.kind == EntryKind.borrow) &&
          e.dueDate != null)) {
        final unit = p.findWallet(e.walletId)?.currency ?? p.currency;
        final left = p.debt(
            borrowed: e.kind == EntryKind.borrow,
            personId: e.personId,
            unit: unit);
        if (left <= 0) continue;
        final due = e.dueDate!;
        for (final before in [1, 0]) {
          final at = DateTime(due.year, due.month, due.day - before, 9);
          if (!at.isAfter(now) || id > _debtBase + 60) continue;
          await _plugin.zonedSchedule(
              id: id++,
              title: e.kind == EntryKind.lend
                  ? 'Đến hạn thu nợ ${p.personName(e.personId)}'
                  : 'Đến hạn trả nợ ${p.personName(e.personId)}',
              body: before == 1
                  ? 'Ngày mai đến hạn, còn lại ${left.toStringAsFixed(0)} $unit.'
                  : 'Hôm nay đến hạn, còn lại ${left.toStringAsFixed(0)} $unit.',
              scheduledDate: _at(at),
              notificationDetails: _details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
        }
      }
    }
  }
}
