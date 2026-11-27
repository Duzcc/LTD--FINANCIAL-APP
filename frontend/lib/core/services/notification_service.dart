import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  Future<void>? _initialization;
  Future<void>? _scheduleUpdates;

  bool get _mobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static const _dailyBase = 100, _debtBase = 1000, _customBase = 2000, _walletBase = 5000;
  static const _details = NotificationDetails(
      android: AndroidNotificationDetails('reminders', 'Nhắc nhở',
          channelDescription: 'Nhắc ghi chép, hạn nợ và cảnh báo vượt ngân sách',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority),
      iOS: DarwinNotificationDetails());

  Future<void> init() async {
    if (!_mobile || _ready) return;
    try {
      await (_initialization ??= _initialize());
      _ready = true;
    } finally {
      _initialization = null;
    }
  }

  Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    final offset = DateTime.now().timeZoneOffset;
    tz.setLocalLocation(offset == const Duration(hours: 7) ? tz.getLocation('Asia/Ho_Chi_Minh') : tz.UTC);
    await _plugin.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
                requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)));
  }

  // Quyền thông báo trên điện thoại
  Future<bool> hasPermission() async {
    if (!_mobile) return false;
    try {
      await init();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final permission = await ios?.checkPermissions();
      return permission?.isEnabled ?? false;
    } catch (error) {
      debugPrint('Không đọc được quyền thông báo: $error');
      return false;
    }
  }

  Future<bool> requestPermission() => _requestPermission().catchError((Object _) => false);

  Future<bool> _requestPermission() async {
    if (!_mobile) return false;
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
    if (!_mobile) return;
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

  // Thông báo vượt ngân sách
  Future<void> budgetExceeded(MoneyBudget budget, String label, double excess) async {
    if (!await hasPermission()) return;
    final month = '${budget.month.month}/${budget.month.year}';
    try {
      await _plugin.show(
        id: 10000 + (budget.id.hashCode & 0x3fffffff),
        title: 'Vượt ngân sách • $label',
        body: 'Tháng $month đã chi vượt ${money(excess, budget.currency)}.',
        notificationDetails: _details,
      );
    } on PlatformException catch (error) {
      debugPrint('Không gửi được cảnh báo ngân sách: ${error.message}');
    }
  }

  Future<void> apply(FinanceProvider p) {
    if (!_mobile) return Future.value();
    final previous = _scheduleUpdates ?? Future<void>.value();
    final next = previous.then((_) => _updateSchedule(p)).catchError((Object error) {
      debugPrint('Không đặt được lịch nhắc: $error');
    });
    _scheduleUpdates = next;
    return next.whenComplete(() {
      if (identical(_scheduleUpdates, next)) _scheduleUpdates = null;
    });
  }

  Future<void> _updateSchedule(FinanceProvider p) async {
    await init();
    // chỉ hủy lịch nhắc, không xóa thông báo đang hiện
    for (final pending in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(id: pending.id);
    }
    if (!await hasPermission()) return;
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
    final reminders = p.reminders.where((r) => !r.expired(now)).take(50).toList();
    for (final (i, r) in reminders.indexed) {
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
      final remaining = p.remainingByLoan();
      final loans = p.entries.where((e) => e.dueDate != null && remaining.containsKey(e.id)).toList()
        ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
      for (final e in loans) {
        final unit = p.findWallet(e.walletId)?.currency ?? p.currency;
        final left = money(remaining[e.id]!, unit);
        final due = e.dueDate!;
        for (final before in [1, 0]) {
          final at = DateTime(due.year, due.month, due.day - before, 9);
          if (!at.isAfter(now) || id > _debtBase + 60) continue;
          await _plugin.zonedSchedule(
              id: id++,
              title: e.kind == EntryKind.lend
                  ? 'Đến hạn thu nợ ${p.personName(e.personId)}'
                  : 'Đến hạn trả nợ ${p.personName(e.personId)}',
              body: before == 1 ? 'Ngày mai đến hạn, còn lại $left.' : 'Hôm nay đến hạn, còn lại $left.',
              scheduledDate: _at(at),
              notificationDetails: _details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
        }
      }
    }
  }
}
