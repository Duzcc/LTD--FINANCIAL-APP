import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/presentation/providers/finance_provider.dart';
import 'package:finance_app/core/widgets/finance_ui.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _customBase = 2000, _walletBase = 5000;
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
    tz.setLocalLocation(offset == const Duration(hours: 7) ? tz.getLocation('Asia/Ho_Chi_Minh') : tz.UTC);
    await _plugin.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
                requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)));
    _ready = true;
  }

  // máy không hỗ trợ thì coi như chưa cho phép
  Future<bool> requestPermission() => _requestPermission().catchError((Object _) => false);

  Future<bool> _requestPermission() async {
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  tz.TZDateTime _at(DateTime local) => tz.TZDateTime.from(local, tz.local);

  Future<void> walletActivity(List<(MoneyWallet, MoneyEntry)> activity) async {
    if (kIsWeb) return;
    await init();
    final byWallet = <MoneyWallet, List<MoneyEntry>>{};
    for (final (w, e) in activity) {
      byWallet.putIfAbsent(w, () => []).add(e);
    }
    for (final MapEntry(key: w, value: entries) in byWallet.entries) {
      final e = entries.first;
      final incoming = e.kind.sign > 0 || (e.kind == EntryKind.transfer && e.destinationId == w.id);
      await _plugin.show(
          id: _walletBase + w.id.hashCode % 1000,
          title: 'Ví ${w.name}',
          body: entries.length == 1
              ? '${e.kind.label} ${incoming ? '+' : '-'}${money(e.amount, w.currency)}'
                  '${e.note.isEmpty ? '' : ' • ${e.note}'}'
              : '${entries.length} giao dịch mới',
          notificationDetails: _details);
    }
  }

  Future<void> apply(FinanceProvider p) async {
    if (kIsWeb) return;
    await init();
    for (final pending in await _plugin.pendingNotificationRequests()) {
      final id = pending.id;
      if ((id >= 100 && id <= 999) || (id >= 1000 && id <= 1060) || (id >= 2000 && id <= 2049)) {
        await _plugin.cancel(id: id);
      }
    }
    final now = DateTime.now();
    for (final (i, reminder) in p.reminders.where((r) => !r.expired(now)).take(50).indexed) {
      await _plugin.zonedSchedule(
          id: _customBase + i,
          title: 'Nhắc nhở chi tiêu',
          body: reminder.title,
          scheduledDate: _at(reminder.nextAfter(now)),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: switch (reminder.repeat) {
            ReminderRepeat.daily => DateTimeComponents.time,
            ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
            ReminderRepeat.monthly => DateTimeComponents.dayOfMonthAndTime,
            ReminderRepeat.none => null,
          });
    }
  }
}
