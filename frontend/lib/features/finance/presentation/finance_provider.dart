import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/core/network/api_client.dart';
import 'package:finance_app/core/utils/dates.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:finance_app/features/auth/data/datasources/session_client.dart';
import 'package:finance_app/features/auth/domain/entities/account_session.dart';
import 'package:finance_app/features/auth/domain/entities/otp_challenge.dart';
import 'package:finance_app/features/finance/data/datasources/finance_local_data_source.dart';
import 'package:finance_app/features/finance/data/datasources/sync_remote_data_source.dart';
import 'package:finance_app/features/finance/data/models/account_snapshot.dart';
import 'package:finance_app/features/finance/data/sync/change_tracker.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/domain/finance_store.dart';
import 'package:finance_app/features/finance/domain/ledger_csv.dart';
import 'package:finance_app/features/finance/domain/ledger_queries.dart';
import 'package:finance_app/features/finance/domain/ledger_rules.dart';

export 'package:finance_app/features/auth/domain/entities/account_session.dart';
export 'package:finance_app/features/auth/domain/entities/otp_challenge.dart';
export 'package:finance_app/features/finance/domain/ledger_queries.dart' show DebtTotals;

class FinanceProvider extends ChangeNotifier with LedgerQueries, LedgerRules implements FinanceStore {
  FinanceProvider({SharedPreferences? storage, ApiClient? api})
      : _local = FinanceLocalDataSource(storage),
        api = api ?? ApiClient() {
    _client = SessionClient(this.api,
        session: () => session,
        serverUrl: () => serverUrl,
        onRefreshed: (next) {
          session = next;
          _changed(sync: false);
        });
    _auth = AuthRemoteDataSource(_client);
    _sync = SyncRemoteDataSource(_client);
    _resetData();
    serverUrl = _local.readServerUrl() ?? ApiClient.defaultBaseUrl;
  }

  final FinanceLocalDataSource _local;
  final ApiClient api;
  late final SessionClient _client;
  late final AuthRemoteDataSource _auth;
  late final SyncRemoteDataSource _sync;
  final ChangeTracker _changes = ChangeTracker();

  static const storageKey = FinanceLocalDataSource.dataKey;
  static const defaultRates = {
    'VND': 1.0,
    'USD': 25400.0,
    'EUR': 27500.0,
    'GBP': 32500.0,
    'JPY': 165.0,
    'CNY': 3500.0,
  };
  static const _defaultCategories = [
    MoneyCategory('food', 'Ăn uống', false, 0),
    MoneyCategory('life', 'Sinh hoạt', false, 1),
    MoneyCategory('house', 'Nhà cửa', false, 2),
    MoneyCategory('self', 'Bản thân', false, 3),
    MoneyCategory('transport', 'Đi lại', false, 4),
    MoneyCategory('health', 'Sức khỏe', false, 5),
    MoneyCategory('child', 'Con cái', false, 6),
    MoneyCategory('salary', 'Lương', true, 7),
    MoneyCategory('bonus', 'Thưởng', true, 8),
    MoneyCategory('business', 'Kinh doanh', true, 11),
    MoneyCategory('other_income', 'Thu nhập khác', true, 12),
  ];

  late List<MoneyWallet> _wallets;
  late List<MoneyEntry> _entries;
  late List<MoneyBudget> _budgets;
  late List<MoneyCategory> _categories;
  late List<MoneyPerson> _people;
  late List<RecurringRule> _recurring;

  @override
  String currency = 'VND';
  @override
  Map<String, double> rates = Map.of(defaultRates);
  String displayName = 'Bạn';
  bool hideBalance = false;
  bool remindersEnabled = false, debtReminders = true;
  List<int> reminderMinutes = [20 * 60];
  List<SpendingReminder> _reminders = [];
  List<SpendingReminder> get reminders => UnmodifiableListView(_reminders);
  void Function(FinanceProvider p)? onScheduleChanged;
  String? recurringError;
  String? storageError;
  @override
  int dataRevision = 0;

  late String serverUrl;
  AccountSession? session;
  bool syncing = false;
  String? syncError;
  DateTime? lastSync;

  Timer? _scheduleTimer;
  Timer? _syncTimer;
  Future<void> _pendingSave = Future.value();
  bool _corruptStorage = false;
  bool _disposed = false;
  bool _profileDirty = false;
  AccountSnapshot? _pendingSnapshot;
  Object? _modelCache;
  static int _sequence = 0;

  @override
  List<MoneyWallet> get wallets => UnmodifiableListView(_wallets);
  @override
  List<MoneyEntry> get entries => UnmodifiableListView(_entries);
  @override
  List<MoneyCategory> get categories => UnmodifiableListView(_categories);
  @override
  List<MoneyPerson> get people => UnmodifiableListView(_people);
  @override
  List<MoneyBudget> get budgets => UnmodifiableListView(_budgets);
  @override
  List<RecurringRule> get recurring => UnmodifiableListView(_recurring);

  bool get emailVerified => session?.emailVerified ?? true;
  @override
  bool get signedIn => session != null;
  @override
  String? get accountId => session?.userId;
  int get pendingChanges => _changes.length + (_profileDirty ? 1 : 0);
  bool get needsLoginDecision => _pendingSnapshot != null;

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  @override
  T cached<T>(T Function() build) {
    final value = _modelCache;
    if (value is T) return value;
    final created = build();
    _modelCache = created;
    return created;
  }

  void _resetData() {
    _wallets = [const MoneyWallet(id: 'cash', name: 'Tiền mặt')];
    _entries = [];
    _budgets = [];
    _categories = List.of(_defaultCategories);
    _people = [const MoneyPerson('self', 'Bản thân', 'Cá nhân')];
    _recurring = [];
    rates = Map.of(defaultRates);
    displayName = 'Bạn';
    currency = 'VND';
    hideBalance = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _scheduleTimer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void restore() {
    // Dữ liệu cũ hỏng thì không ghi đè lên nó, để người dùng còn khôi phục từ bản sao lưu.
    try {
      final saved = _local.read();
      if (saved != null) _applySaved(saved);
    } catch (_) {
      _corruptStorage = true;
      storageError = 'Không đọc được dữ liệu đã lưu. Vui lòng kiểm tra bản sao lưu trước khi tiếp tục.';
    }
  }

  void _applySaved(Map<String, dynamic> j) {
    final saved = AccountSnapshot(j);
    final wallets = saved.wallets, entries = saved.entries, categories = saved.categories;
    final people = saved.people, budgets = saved.budgets, recurring = saved.recurring;
    final reminders = ((j['reminderMinutes'] as List?) ?? const [1200]).map((v) => (v as num).toInt()).toList();
    _wallets = wallets;
    _entries = entries;
    _categories = categories;
    _people = people;
    _budgets = budgets;
    _recurring = recurring;
    rates = _readRates(j['rates']);
    remindersEnabled = j['remindersEnabled'] == true;
    debtReminders = j['debtReminders'] != false;
    reminderMinutes = reminders;
    _reminders = [
      for (final r in (j['spendingReminders'] as List?) ?? const [])
        SpendingReminder.fromJson((r as Map).cast<String, dynamic>())
    ];
    displayName = j['displayName'] ?? 'Bạn';
    currency = j['currency'] ?? 'VND';
    hideBalance = j['hideBalance'] ?? false;
    session = AccountSession.fromJson(j['session'], defaultBaseUrl: ApiClient.defaultBaseUrl);
    _changes.restore((j['dirty'] as List?) ?? const []);
    _profileDirty = j['profileDirty'] == true;
    lastSync = DateTime.tryParse('${j['lastSync'] ?? ''}')?.toLocal();
  }

  Future<void> flush() => _pendingSave;
  void retrySave() => _changed(sync: false);

  Map<String, dynamic> _toJson() => {
        'wallets': _wallets.map((v) => v.toJson()).toList(),
        'entries': _entries.map((v) => v.toJson()).toList(),
        'categories': _categories.map((v) => v.toJson()).toList(),
        'people': _people.map((v) => v.toJson()).toList(),
        'budgets': _budgets.map((v) => v.toJson()).toList(),
        'recurring': _recurring.map((v) => v.toJson()).toList(),
        'rates': rates,
        'remindersEnabled': remindersEnabled,
        'debtReminders': debtReminders,
        'reminderMinutes': reminderMinutes,
        'spendingReminders': _reminders.map((r) => r.toJson()).toList(),
        'displayName': displayName,
        'currency': currency,
        'hideBalance': hideBalance,
        'session': session?.toJson(),
        'dirty': _changes.keys,
        'profileDirty': _profileDirty,
        'lastSync': lastSync?.toUtc().toIso8601String(),
      };

  void _changed({bool sync = true}) {
    if (_corruptStorage) {
      _notify();
      return;
    }
    final data = _toJson();
    _pendingSave = _pendingSave.then((_) async {
      if (_local.persistent) {
        storageError = await _local.write(data) ? null : 'Chưa lưu được trên thiết bị. Hãy kiểm tra dung lượng trống.';
      }
      _notify();
    });
    if (sync && session != null) _scheduleSync();
    if (onScheduleChanged != null) {
      _scheduleTimer?.cancel();
      _scheduleTimer = Timer(const Duration(seconds: 2), () {
        if (!_disposed) onScheduleChanged?.call(this);
      });
    }
    _modelCache = null;
    dataRevision++;
    _notify();
  }

  void _mark(String entity, String id) {
    if (session != null) _changes.mark(entity, id);
  }

  void _markProfile() {
    if (session != null) _profileDirty = true;
  }

  static Map<String, double> _readRates(Object? v) {
    final result = Map.of(defaultRates);
    if (v is Map) {
      v.forEach((k, value) {
        if (value is num && value > 0) result['$k'] = value.toDouble();
      });
    }
    result['VND'] = 1;
    return result;
  }

  void _put<T>(List<T> list, T value, bool Function(T) sameId) {
    final index = list.indexWhere(sameId);
    if (index < 0) {
      list.add(value);
    } else {
      list[index] = value;
    }
  }

  void setRate(String unit, double value) {
    if (unit == 'VND' || !value.isFinite || value <= 0) throw ArgumentError('Tỷ giá phải lớn hơn 0.');
    rates[unit] = value;
    _markProfile();
    _changed();
  }

  void setReminders({bool? enabled, bool? debts, List<int>? minutes}) {
    remindersEnabled = enabled ?? remindersEnabled;
    debtReminders = debts ?? debtReminders;
    if (minutes != null) reminderMinutes = (minutes.toSet().toList()..sort());
    _changed(sync: false);
  }

  void saveReminder(SpendingReminder r) {
    if (r.title.trim().isEmpty) throw ArgumentError('Nhập nội dung cần nhắc.');
    _put(_reminders, r, (x) => x.id == r.id);
    _changed(sync: false);
  }

  void deleteReminder(String id) {
    _reminders.removeWhere((r) => r.id == id);
    _changed(sync: false);
  }

  void preferences({String? name, String? unit, bool? hidden}) {
    if (name != null && name.trim().isNotEmpty) displayName = name.trim();
    currency = unit ?? currency;
    hideBalance = hidden ?? hideBalance;
    _markProfile();
    _changed();
  }

  void saveWallet(MoneyWallet value) {
    checkWallet(value);
    _put(_wallets, value, (w) => w.id == value.id);
    _mark('wallets', value.id);
    _changed();
  }

  void deleteWallet(String id, {bool cascade = false}) {
    checkWalletRemovable(id, cascade: cascade);
    bool usesWallet(String walletId, String? destinationId) => walletId == id || destinationId == id;
    for (final e in _entries.where((e) => usesWallet(e.walletId, e.destinationId))) {
      _mark('entries', e.id);
    }
    for (final b in _budgets.where((b) => b.walletId == id)) {
      _mark('budgets', b.id);
    }
    for (final r in _recurring.where((r) => usesWallet(r.walletId, r.destinationId))) {
      _mark('recurring', r.id);
    }
    _entries.removeWhere((e) => usesWallet(e.walletId, e.destinationId));
    _budgets.removeWhere((b) => b.walletId == id);
    _recurring.removeWhere((r) => usesWallet(r.walletId, r.destinationId));
    _wallets.removeWhere((v) => v.id == id);
    _mark('wallets', id);
    _changed();
  }

  void saveEntry(MoneyEntry value) {
    checkEntry(value);
    _put(_entries, value, (e) => e.id == value.id);
    _mark('entries', value.id);
    _changed();
  }

  void deleteEntry(String id) {
    _entries.removeWhere((e) => e.id == id);
    _mark('entries', id);
    _changed();
  }

  void setPhoto(String entryId, String? path) {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i < 0) return;
    _entries[i] = _entries[i].copyWith(photo: path, clearPhoto: path == null);
    _changed(sync: false);
  }

  void saveRecurring(RecurringRule r) {
    checkRecurring(r);
    _put(_recurring, r, (v) => v.id == r.id);
    _mark('recurring', r.id);
    recurringError = null;
    _changed();
  }

  void deleteRecurring(String id) {
    _recurring.removeWhere((r) => r.id == id);
    _mark('recurring', id);
    _changed();
  }

  int runRecurring({DateTime? now}) {
    final until = now ?? DateTime.now();
    var created = 0;
    for (var i = 0; i < _recurring.length; i++) {
      var rule = _recurring[i];
      if (!rule.active) continue;
      bool pastEnd(DateTime d) => rule.endDate != null && dateOnly(d).isAfter(dateOnly(rule.endDate!));
      var next = rule.upcoming;
      var guard = 0;
      var changed = false;
      while (!next.isAfter(until) && guard++ < 400 && !pastEnd(next)) {
        final id = rule.occurrenceId(next);
        if (!_entries.any((e) => e.id == id)) {
          final occurrence = MoneyEntry(
              id: id,
              kind: rule.kind,
              amount: rule.amount,
              walletId: rule.walletId,
              date: next,
              destinationId: rule.destinationId,
              categoryId: rule.categoryId,
              personId: rule.personId,
              note: rule.note,
              recurringId: rule.id);
          // Một lần lặp không hợp lệ (ví dụ ví đã hết tiền) thì tạm dừng quy tắc đó và báo cho người dùng.
          try {
            saveEntry(occurrence);
            created++;
          } on ArgumentError catch (e) {
            recurringError =
                'Không tạo được giao dịch định kỳ "${rule.note.isEmpty ? rule.kind.label : rule.note}": ${e.message}';
            rule = rule.copyWith(active: false);
            changed = true;
            break;
          }
        }
        next = rule.nextAfter(next);
        changed = true;
      }
      if (rule.active && pastEnd(next)) {
        rule = rule.copyWith(active: false);
        changed = true;
      }
      if (changed) {
        _recurring[i] = rule.copyWith(nextDate: next);
        _mark('recurring', rule.id);
      }
    }
    if (created > 0 || recurringError != null) _changed();
    return created;
  }

  void saveCategory(MoneyCategory c) {
    checkCategory(c);
    _put(_categories, c, (v) => v.id == c.id);
    _mark('categories', c.id);
    _changed();
  }

  void deleteCategory(String id) {
    checkCategoryRemovable(id);
    _categories.removeWhere((c) => c.id == id);
    _mark('categories', id);
    _changed();
  }

  void savePerson(MoneyPerson p) {
    checkPerson(p);
    _put(_people, p, (v) => v.id == p.id);
    _mark('people', p.id);
    _changed();
  }

  void deletePerson(String id) {
    checkPersonRemovable(id);
    _people.removeWhere((p) => p.id == id);
    _mark('people', id);
    _changed();
  }

  void saveBudget(MoneyBudget b) {
    checkBudget(b);
    _put(_budgets, b, (v) => v.id == b.id);
    _mark('budgets', b.id);
    _changed();
  }

  void deleteBudget(String id) {
    _budgets.removeWhere((b) => b.id == id);
    _mark('budgets', id);
    _changed();
  }

  int copyBudgets(DateTime from, DateTime to, {String? unit}) {
    final source = _budgets.where((b) =>
        b.month.year == from.year && b.month.month == from.month && b.currency == (unit ?? currency));
    var count = 0;
    for (final b in source.toList()) {
      final copy = MoneyBudget(
          id: newId(),
          categoryId: b.categoryId,
          month: DateTime(to.year, to.month),
          amount: b.amount,
          walletId: b.walletId,
          currency: b.currency,
          income: b.income);
      if (budgetError(copy) != null) continue;
      saveBudget(copy);
      count++;
    }
    return count;
  }

  String exportCsv() => ledgerCsv(this);

  void setServerUrl(String url) {
    serverUrl = ApiClient.normalize(url);
    _local.writeServerUrl(serverUrl);
    _notify();
  }

  Future<String?> checkServer([String? url]) => api
      .send('GET', url ?? serverUrl, '/health')
      .then<String?>((r) => r['status'] == 'ok' ? null : 'Máy chủ không phản hồi đúng.')
      .onError<ApiException>((e, _) => e.message);

  Future<OtpChallenge> signIn({required String email, required String password}) =>
      _auth.login(email.trim().toLowerCase(), password);

  Future<OtpChallenge> register({required String name, required String email, required String password}) =>
      _auth.register(name.trim().replaceAll(RegExp(r'\s+'), ' '), email.trim().toLowerCase(), password);

  Future<bool> verifyOtp(OtpChallenge challenge, String code) async =>
      _startSession(await _auth.verifyOtp(challenge, code.trim()));

  Future<OtpChallenge> resendOtp(OtpChallenge challenge) => _auth.resendOtp(challenge);

  Future<String?> forgotPassword(String email) => _auth.forgotPassword(email.trim());

  Future<bool> resetPassword({required String email, required String code, required String newPassword}) async =>
      _startSession(await _auth.resetPassword(email.trim(), code.trim(), newPassword));

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final r = await _auth.changePassword(oldPassword, newPassword);
    session = session!.withToken(r['token'] as String, refresh: r['refreshToken'] as String?);
    syncError = null;
    _changed(sync: false);
  }

  Future<void> verifyEmail(String code) async {
    await _auth.verifyEmail(code.trim());
    session = session!.withToken(session!.token, verified: true);
    _changed(sync: false);
  }

  Future<String?> resendVerification() => _auth.resendVerification();

  Future<Map<String, dynamic>> _signedInRequest(String method, String path,
      {Object? body, required bool pushFirst, required String offlineMessage}) async {
    if (session == null) throw ApiException(0, 'OFFLINE', offlineMessage);
    if (pushFirst && pendingChanges > 0) await syncNow(pull: false);
    return _client.send(method, path, body: body);
  }

  @override
  Future<Map<String, dynamic>> aiRequest(String method, String path, {Object? body, bool pushFirst = true}) =>
      _signedInRequest(method, '/ai$path',
          body: body, pushFirst: pushFirst, offlineMessage: 'Cần đăng nhập để dùng AI máy chủ.');

  @override
  Future<Map<String, dynamic>> bankRequest(String method, String path, {Object? body}) =>
      _signedInRequest(method, '/bank$path',
          body: body, pushFirst: true, offlineMessage: 'Cần đăng nhập để đối soát chuyển khoản tự động.');

  Future<bool> _startSession(Map<String, dynamic> r) async {
    final user = r['user'] as Map<String, dynamic>;
    session = AccountSession(
        baseUrl: serverUrl,
        token: r['token'] as String,
        email: '${user['email']}',
        userId: '${user['id']}',
        refreshToken: r['refreshToken'] as String?,
        emailVerified: user['emailVerified'] != false);
    displayName = '${user['name'] ?? displayName}';
    syncError = null;
    final AccountSnapshot snapshot;
    // Tải dữ liệu thất bại thì hủy đăng nhập, tránh trạng thái đã đăng nhập mà không có dữ liệu.
    try {
      snapshot = AccountSnapshot(await _sync.fetchSnapshot());
    } catch (_) {
      session = null;
      rethrow;
    }
    if (!snapshot.hasData) {
      await _uploadAllLocal();
      return false;
    }
    if (_localHasData) {
      _pendingSnapshot = snapshot;
      _notify();
      return true;
    }
    _applySnapshot(snapshot);
    return false;
  }

  void cancelLogin() {
    _pendingSnapshot = null;
    session = null;
    _notify();
  }

  Future<void> resolveLogin({required bool useAccount}) async {
    final snapshot = _pendingSnapshot;
    _pendingSnapshot = null;
    if (session == null) return;
    if (useAccount && snapshot != null) {
      _applySnapshot(snapshot);
    } else {
      await _uploadAllLocal();
    }
  }

  bool get _localHasData =>
      _entries.isNotEmpty ||
      _recurring.isNotEmpty ||
      _budgets.isNotEmpty ||
      _wallets.length > 1 ||
      _people.length > 1 ||
      _wallets.any((w) => w.opening != 0);

  Future<void> _uploadAllLocal() async {
    final all = <String, Iterable<dynamic>>{
      'wallets': _wallets,
      'categories': _categories,
      'people': _people,
      'entries': _entries,
      'budgets': _budgets,
      'recurring': _recurring,
    };
    all.forEach((entity, items) {
      for (final item in items) {
        _mark(entity, item.id as String);
      }
    });
    _changed(sync: false);
    await syncNow();
  }

  void _applySnapshot(AccountSnapshot s) {
    final photos = {
      for (final e in _entries)
        if (e.photo != null) e.id: e.photo!
    };
    _wallets = s.wallets;
    _categories = s.categories;
    _people = s.people;
    _entries = [for (final e in s.entries) photos[e.id] == null ? e : e.copyWith(photo: photos[e.id])];
    _budgets = s.budgets;
    _recurring = s.recurring;
    final user = s.user;
    if (user != null) {
      displayName = '${user['name'] ?? displayName}';
      currency = '${user['currency'] ?? currency}';
      hideBalance = user['hideBalance'] == true;
      if (user['rates'] is Map) rates = _readRates(user['rates']);
      final current = session;
      if (current != null && user['emailVerified'] != null) {
        session = current.withToken(current.token, verified: user['emailVerified'] != false);
      }
    }
    _changes.clear();
    _profileDirty = false;
    lastSync = DateTime.now();
    syncError = null;
    _changed(sync: false);
    runRecurring();
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 800), () => syncNow(pull: false));
  }

  Future<void> syncNow({bool pull = true}) async {
    if (session == null || syncing) return;
    syncing = true;
    _notify();
    try {
      await _push();
      if (pull && _changes.isEmpty && !_profileDirty) {
        final snapshot = AccountSnapshot(await _sync.fetchSnapshot());
        if (_changes.isEmpty && !_profileDirty) _applySnapshot(snapshot);
      }
      lastSync = DateTime.now();
      syncError = null;
    } on ApiException catch (e) {
      syncError = e.isUnauthorized ? 'Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất và đăng nhập lại.' : e.message;
    } finally {
      syncing = false;
      _changed(sync: false);
    }
  }

  Map<String, dynamic>? _jsonOf(String entity, String id) {
    final Iterable<dynamic> list = switch (entity) {
      'wallets' => _wallets,
      'categories' => _categories,
      'people' => _people,
      'recurring' => _recurring,
      'entries' => _entries,
      _ => _budgets,
    };
    for (final v in list) {
      if (v.id == id) return (v.toJson() as Map).cast<String, dynamic>();
    }
    return null;
  }

  // Đánh dấu "đã gửi" trước khi gửi, để thay đổi xảy ra trong lúc chờ vẫn được gửi ở lần sau.
  Future<void> _pushProfile() async {
    _profileDirty = false;
    try {
      await _auth.updateProfile({
        if (validateName(displayName) == null) 'name': displayName,
        'currency': currency,
        'hideBalance': hideBalance,
        'rates': rates,
      });
    } catch (_) {
      _profileDirty = true;
      rethrow;
    }
  }

  Future<void> _push() async {
    if (_profileDirty) await _pushProfile();
    if (_changes.isEmpty) return;
    final (:ops, :versions) = _changes.pending(_jsonOf);
    try {
      await _sync.pushBatch([for (final op in ops) op.toJson()]);
      _changes.acknowledge(ops, versions);
    } on ApiException catch (e) {
      // Máy chủ đã lưu được một phần: bỏ các thay đổi đã lưu khỏi hàng chờ, phần còn lại gửi lần sau.
      final applied = e.body?['applied'];
      if (applied is! int) rethrow;
      _changes.acknowledge(ops.take(applied), versions);
      throw ApiException(e.status, e.code, 'Chưa đồng bộ được một thay đổi: ${e.message}');
    }
  }

  Future<void> discardLocalChanges() async {
    if (session == null) return;
    _changes.clear();
    _profileDirty = false;
    await syncNow();
  }

  Future<void> signOut({bool revoke = true, bool everywhere = false}) async {
    _syncTimer?.cancel();
    final current = session;
    if (revoke && current != null) {
      await _auth
          .logout(everywhere: everywhere, refreshToken: current.refreshToken)
          .onError<ApiException>((_, __) {});
    }
    session = null;
    _pendingSnapshot = null;
    _changes.clear();
    _profileDirty = false;
    lastSync = null;
    syncError = null;
    _resetData();
    await _pendingSave;
    await _local.clear();
    _notify();
  }

  Future<void> deleteAccount(String password) async {
    await _auth.deleteAccount(password);
    await signOut(revoke: false);
  }
}
