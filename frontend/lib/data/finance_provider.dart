import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finance_app/data/models/finance_models.dart';
import 'package:finance_app/core/network/api_client.dart';

/// Phiên đăng nhập với backend (máy chủ API tách riêng khỏi ứng dụng).
class AccountSession {
  const AccountSession(
      {required this.baseUrl,
      required this.token,
      required this.email,
      required this.userId,
      this.refreshToken,
      this.emailVerified = true});
  final String baseUrl, token, email, userId;
  final String? refreshToken;
  final bool emailVerified;
  AccountSession withToken(String value, {String? refresh, bool? verified}) =>
      AccountSession(
          baseUrl: baseUrl,
          token: value,
          email: email,
          userId: userId,
          refreshToken: refresh ?? refreshToken,
          emailVerified: verified ?? emailVerified);
  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'token': token,
        'email': email,
        'userId': userId,
        'refreshToken': refreshToken,
        'emailVerified': emailVerified
      };
  static AccountSession? fromJson(Object? j) {
    if (j is! Map) return null;
    final token = j['token'];
    if (token is! String || token.isEmpty) return null;
    return AccountSession(
        baseUrl: '${j['baseUrl'] ?? ApiClient.defaultBaseUrl}',
        token: token,
        email: '${j['email'] ?? ''}',
        userId: '${j['userId'] ?? ''}',
        refreshToken: j['refreshToken'] as String?,
        emailVerified: j['emailVerified'] != false);
  }
}

/// Dư nợ: tổng gốc phát sinh và phần đã thanh toán.
typedef DebtTotals = ({double principal, double settled});

/// Một sổ cái duy nhất là nguồn dữ liệu cho số dư, báo cáo và ngân sách.
/// Số dư ban đầu không đổi khi sửa/xóa giao dịch: số dư hiện tại luôn được tính lại.
///
/// Khi đăng nhập, mọi thay đổi được ghi nhận vào hàng đợi đồng bộ (theo khóa
/// "loại:mã") và gửi lên backend qua `POST /api/sync/batch`; ứng dụng vẫn dùng
/// được khi mất mạng và sẽ đồng bộ lại khi có kết nối.
class FinanceProvider extends ChangeNotifier {
  FinanceProvider({SharedPreferences? storage, ApiClient? api})
      : _storage = storage,
        api = api ?? ApiClient() {
    _resetData();
    serverUrl = _storage?.getString(serverKey) ?? ApiClient.defaultBaseUrl;
  }
  final SharedPreferences? _storage;
  final ApiClient api;
  static const storageKey = 'finance_data_v1';
  static const serverKey = 'finance_server_url';

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
  String displayName = 'Bạn', currency = 'VND';

  /// Tỷ giá quy đổi: giá trị 1 đơn vị tiền tệ tính bằng VND.
  static const defaultRates = {
    'VND': 1.0,
    'USD': 25400.0,
    'EUR': 27500.0,
    'GBP': 32500.0,
    'JPY': 165.0,
    'CNY': 3500.0,
  };
  Map<String, double> rates = Map.of(defaultRates);

  // ---- Nhắc nhở (chỉ lưu trên thiết bị) ----
  bool remindersEnabled = false, debtReminders = true;
  List<int> reminderMinutes = [20 * 60];

  /// Được gán ở main.dart để lên lịch thông báo hệ điều hành; null trong kiểm thử.
  void Function(FinanceProvider p)? onScheduleChanged;
  Timer? _scheduleTimer;
  String? recurringError;
  bool hideBalance = false;
  String? storageError;
  Future<void> _pendingSave = Future.value();
  bool _corruptStorage = false;
  bool _disposed = false;

  // ---- Đồng bộ ----
  late String serverUrl;
  AccountSession? session;
  final Map<String, int> _dirty = {};
  int _clock = 0;
  bool _profileDirty = false;
  bool syncing = false;
  String? syncError;
  DateTime? lastSync;
  Timer? _syncTimer;
  Map<String, dynamic>? _pendingSnapshot;

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

  List<MoneyWallet> get wallets => List.unmodifiable(_wallets);
  List<MoneyEntry> get entries => List.unmodifiable(_entries);
  List<MoneyCategory> get categories => List.unmodifiable(_categories);
  List<MoneyPerson> get people => List.unmodifiable(_people);
  List<MoneyBudget> get budgets => List.unmodifiable(_budgets);
  List<RecurringRule> get recurring => List.unmodifiable(_recurring);
  bool get emailVerified => session?.emailVerified ?? true;
  bool get signedIn => session != null;
  int get pendingChanges => _dirty.length + (_profileDirty ? 1 : 0);
  bool get needsLoginDecision => _pendingSnapshot != null;

  /// Hủy đăng nhập khi người dùng chưa chọn cách xử lý dữ liệu.
  void cancelLogin() {
    _pendingSnapshot = null;
    session = null;
    _notify();
  }
  static int _sequence = 0;
  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';

  // ---------------------------------------------------------------- lưu trữ
  void restore() {
    final raw = _storage?.getString(storageKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final wallets =
          (j['wallets'] as List).map((v) => MoneyWallet.fromJson(v)).toList();
      final entries =
          (j['entries'] as List).map((v) => MoneyEntry.fromJson(v)).toList();
      final categories = (j['categories'] as List)
          .map((v) => MoneyCategory.fromJson(v))
          .toList();
      final people =
          (j['people'] as List).map((v) => MoneyPerson.fromJson(v)).toList();
      final budgets =
          (j['budgets'] as List).map((v) => MoneyBudget.fromJson(v)).toList();
      _wallets = wallets;
      _entries = entries;
      _categories = categories;
      _people = people;
      _budgets = budgets;
      _recurring = ((j['recurring'] as List?) ?? const [])
          .map((v) => RecurringRule.fromJson(v))
          .toList();
      rates = _readRates(j['rates']);
      remindersEnabled = j['remindersEnabled'] == true;
      debtReminders = j['debtReminders'] != false;
      reminderMinutes = ((j['reminderMinutes'] as List?) ?? const [1200])
          .map((v) => (v as num).toInt())
          .toList();
      displayName = j['displayName'] ?? 'Bạn';
      currency = j['currency'] ?? 'VND';
      hideBalance = j['hideBalance'] ?? false;
      session = AccountSession.fromJson(j['session']);
      _dirty.clear();
      for (final k in (j['dirty'] as List?) ?? const []) {
        _dirty['$k'] = ++_clock;
      }
      _profileDirty = j['profileDirty'] == true;
      lastSync = DateTime.tryParse('${j['lastSync'] ?? ''}')?.toLocal();
    } catch (_) {
      _corruptStorage = true;
      storageError =
          'Không đọc được dữ liệu đã lưu. Vui lòng kiểm tra bản sao lưu trước khi tiếp tục.';
    }
  }

  Future<void> flush() => _pendingSave;
  void retrySave() => _changed(sync: false);

  void _changed({bool sync = true}) {
    if (_corruptStorage) {
      _notify();
      return;
    }
    final raw = jsonEncode({
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
      'displayName': displayName,
      'currency': currency,
      'hideBalance': hideBalance,
      'session': session?.toJson(),
      'dirty': _dirty.keys.toList(),
      'profileDirty': _profileDirty,
      'lastSync': lastSync?.toUtc().toIso8601String(),
    });
    final storage = _storage;
    _pendingSave = _pendingSave.then((_) async {
      try {
        if (storage != null && !await storage.setString(storageKey, raw)) {
          throw StateError('save failed');
        }
        if (storage != null) storageError = null;
      } catch (_) {
        storageError =
            'Chưa lưu được trên thiết bị. Hãy kiểm tra dung lượng trống.';
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
    _notify();
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

  /// Quy đổi [value] từ tiền tệ [from] sang [to] theo bảng tỷ giá.
  double convert(double value, String from, String to) =>
      from == to ? value : value * (rates[from] ?? 1) / (rates[to] ?? 1);

  /// Tổng số dư mọi ví (mọi tiền tệ) quy đổi về [unit].
  double convertedTotal(String unit, {bool spendableOnly = false}) => _wallets
      .where((w) => !w.excluded && (!spendableOnly || !w.savings))
      .fold(0, (s, w) => s + convert(balance(w.id), w.currency, unit));

  bool get hasManyCurrencies => _wallets.map((w) => w.currency).toSet().length > 1;

  void setRate(String unit, double value) {
    if (unit == 'VND' || !value.isFinite || value <= 0) {
      throw ArgumentError('Tỷ giá phải lớn hơn 0.');
    }
    rates[unit] = value;
    if (session != null) _profileDirty = true;
    _changed();
  }

  void setReminders({bool? enabled, bool? debts, List<int>? minutes}) {
    remindersEnabled = enabled ?? remindersEnabled;
    debtReminders = debts ?? debtReminders;
    if (minutes != null) reminderMinutes = (minutes.toSet().toList()..sort());
    _changed(sync: false);
  }

  // Mô hình gợi ý danh mục được huấn luyện lại khi dữ liệu thay đổi.
  Object? _modelCache;
  T cached<T>(T Function() build) {
    final value = _modelCache;
    if (value is T) return value;
    final created = build();
    _modelCache = created;
    return created;
  }

  void _mark(String entity, String id) {
    if (session != null) _dirty['$entity:$id'] = ++_clock;
  }

  // ---------------------------------------------------------------- tra cứu
  MoneyWallet wallet(String id) => _wallets.firstWhere((w) => w.id == id);
  MoneyWallet? findWallet(String? id) {
    for (final w in _wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  MoneyCategory? category(String? id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String personName(String? id) {
    for (final p in _people) {
      if (p.id == id) return p.name;
    }
    return '';
  }

  String _unitOf(MoneyEntry e) => findWallet(e.walletId)?.currency ?? '';

  double balance(String id) => _entries.fold(
      wallet(id).opening,
      (sum, e) =>
          sum +
          (e.walletId == id ? e.amount * e.kind.sign : 0) +
          (e.kind == EntryKind.transfer && e.destinationId == id
              ? e.amount
              : 0));

  /// Tổng số dư các ví được tính vào tổng. [spendableOnly]: chỉ tính tài sản
  /// có thể dùng ngay (bỏ qua ví tiết kiệm).
  double totalBalance(String unit, {bool spendableOnly = false}) => _wallets
      .where((w) =>
          !w.excluded && w.currency == unit && (!spendableOnly || !w.savings))
      .fold(0, (sum, w) => sum + balance(w.id));

  int walletReferences(String id) =>
      _entries.where((e) => e.walletId == id || e.destinationId == id).length +
      _budgets.where((b) => b.walletId == id).length +
      _recurring.where((r) => r.walletId == id || r.destinationId == id).length;

  List<MoneyEntry> inMonth(DateTime month, {String? walletId, String? unit}) =>
      between(DateTime(month.year, month.month),
          DateTime(month.year, month.month + 1),
          walletId: walletId, unit: unit);

  /// Giao dịch có from <= ngày < to, mới nhất trước.
  List<MoneyEntry> between(DateTime from, DateTime to,
          {String? walletId, String? unit}) =>
      _entries
          .where((e) =>
              !e.date.isBefore(from) &&
              e.date.isBefore(to) &&
              (walletId == null ||
                  e.walletId == walletId ||
                  e.destinationId == walletId) &&
              (unit == null || _unitOf(e) == unit))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  double sumBetween(DateTime from, DateTime to,
          {required bool income,
          String? walletId,
          String? categoryId,
          String? unit}) =>
      between(from, to, walletId: walletId, unit: unit ?? currency)
          .where((e) =>
              !e.excluded &&
              (walletId == null || e.walletId == walletId) &&
              (income ? e.kind.isIncome : e.kind.isExpense) &&
              (categoryId == null || e.categoryId == categoryId))
          .fold(0, (s, e) => s + e.amount);

  double total(DateTime month,
          {required bool income,
          String? walletId,
          String? categoryId,
          String? unit}) =>
      sumBetween(DateTime(month.year, month.month),
          DateTime(month.year, month.month + 1),
          income: income, walletId: walletId, categoryId: categoryId, unit: unit);

  bool budgetIncome(MoneyBudget b) =>
      b.categoryId == null ? b.income : category(b.categoryId)?.income ?? false;

  double used(MoneyBudget b) => total(b.month,
      income: budgetIncome(b),
      walletId: b.walletId,
      categoryId: b.categoryId,
      unit: b.currency);

  /// Mục tiêu tổng của tháng (không theo danh mục).
  MoneyBudget? overallBudget(DateTime month,
      {required bool income, String? unit}) {
    for (final b in _budgets) {
      if (b.categoryId == null &&
          b.income == income &&
          b.currency == (unit ?? currency) &&
          b.month.year == month.year &&
          b.month.month == month.month) {
        return b;
      }
    }
    return null;
  }

  /// Dư nợ còn lại: [borrowed] = true → số phải trả, false → số cần thu.
  double debt(
          {required bool borrowed,
          String? personId,
          String? unit,
          String? excludeId}) =>
      _entries
          .where((e) =>
              e.id != excludeId &&
              (personId == null || e.personId == personId) &&
              _unitOf(e) == (unit ?? currency))
          .fold(
              0,
              (s, e) =>
                  s +
                  (e.kind == (borrowed ? EntryKind.borrow : EntryKind.lend)
                      ? e.amount
                      : e.kind ==
                              (borrowed ? EntryKind.repay : EntryKind.collect)
                          ? -e.amount
                          : 0));

  DebtTotals debtTotals(
      {required bool borrowed, String? personId, String? unit}) {
    var principal = 0.0, settled = 0.0;
    for (final e in _entries) {
      if (personId != null && e.personId != personId) continue;
      if (_unitOf(e) != (unit ?? currency)) continue;
      if (e.kind == (borrowed ? EntryKind.borrow : EntryKind.lend)) {
        principal += e.amount;
      }
      if (e.kind == (borrowed ? EntryKind.repay : EntryKind.collect)) {
        settled += e.amount;
      }
    }
    return (principal: principal, settled: settled);
  }

  // ---------------------------------------------------------------- ví
  void saveWallet(MoneyWallet value) {
    if (value.name.trim().isEmpty ||
        !value.opening.isFinite ||
        value.opening < 0 ||
        !value.target.isFinite ||
        value.target < 0) {
      throw ArgumentError('Nhập tên ví và số tiền hợp lệ, không âm.');
    }
    if (_wallets.any((w) =>
        w.id != value.id &&
        w.name.trim().toLowerCase() == value.name.trim().toLowerCase())) {
      throw ArgumentError('Tên ví đã tồn tại. Vui lòng đặt tên khác.');
    }
    if (value.startDate != null &&
        value.deadline != null &&
        DateUtilsDate.day(value.deadline!)
            .isBefore(DateUtilsDate.day(value.startDate!))) {
      throw ArgumentError('Ngày kết thúc phải sau ngày bắt đầu.');
    }
    final index = _wallets.indexWhere((v) => v.id == value.id);
    if (index >= 0 &&
        _wallets[index].currency != value.currency &&
        walletReferences(value.id) > 0) {
      throw ArgumentError(
          'Ví đã có giao dịch hoặc ngân sách nên không thể đổi tiền tệ.');
    }
    if (index < 0) {
      _wallets.add(value);
    } else {
      _wallets[index] = value;
    }
    _mark('wallets', value.id);
    _changed();
  }

  /// Xóa ví. Khi [cascade] = true, xóa luôn giao dịch và ngân sách liên quan.
  void deleteWallet(String id, {bool cascade = false}) {
    if (walletReferences(id) > 0) {
      if (!cascade) {
        throw ArgumentError(
            'Ví đang có giao dịch hoặc ngân sách. Hãy xử lý các dữ liệu liên quan trước.');
      }
      for (final e in _entries
          .where((e) => e.walletId == id || e.destinationId == id)) {
        _mark('entries', e.id);
      }
      for (final b in _budgets.where((b) => b.walletId == id)) {
        _mark('budgets', b.id);
      }
      for (final r in _recurring
          .where((r) => r.walletId == id || r.destinationId == id)) {
        _mark('recurring', r.id);
      }
      _entries.removeWhere((e) => e.walletId == id || e.destinationId == id);
      _budgets.removeWhere((b) => b.walletId == id);
      _recurring
          .removeWhere((r) => r.walletId == id || r.destinationId == id);
    }
    _wallets.removeWhere((v) => v.id == id);
    _mark('wallets', id);
    _changed();
  }

  // ---------------------------------------------------------------- giao dịch
  void saveEntry(MoneyEntry value) {
    _validateEntry(value);
    final index = _entries.indexWhere((e) => e.id == value.id);
    if (index < 0) {
      _entries.add(value);
    } else {
      _entries[index] = value;
    }
    _mark('entries', value.id);
    _changed();
  }

  void _validateEntry(MoneyEntry value, {bool checkDebt = true}) {
    if (!value.amount.isFinite || value.amount <= 0) {
      throw ArgumentError('Số tiền phải lớn hơn 0.');
    }
    final source = findWallet(value.walletId);
    if (source == null) throw ArgumentError('Vui lòng chọn ví hợp lệ.');
    if (value.kind == EntryKind.transfer) {
      if (value.destinationId == null ||
          value.destinationId == value.walletId ||
          findWallet(value.destinationId) == null) {
        throw ArgumentError('Chọn hai ví khác nhau.');
      }
      if (wallet(value.destinationId!).currency != source.currency) {
        throw ArgumentError('Chỉ chuyển giữa hai ví cùng tiền tệ.');
      }
    }
    if (value.kind.isExpense || value.kind.isIncome) {
      final c = category(value.categoryId);
      if (c == null || c.income != value.kind.isIncome) {
        throw ArgumentError('Chọn danh mục phù hợp với giao dịch.');
      }
    }
    if (value.kind.isDebt && personName(value.personId).isEmpty) {
      throw ArgumentError('Chọn đối tượng cho giao dịch vay/nợ.');
    }
    if (value.dueDate != null &&
        DateUtilsDate.day(value.dueDate!)
            .isBefore(DateUtilsDate.day(value.date))) {
      throw ArgumentError('Ngày đến hạn không được trước ngày giao dịch.');
    }
    if (checkDebt &&
        (value.kind == EntryKind.collect || value.kind == EntryKind.repay)) {
      final repay = value.kind == EntryKind.repay;
      final left = debt(
          borrowed: repay,
          personId: value.personId,
          unit: source.currency,
          excludeId: value.id);
      if (value.amount > left + 1e-9) {
        throw ArgumentError(left <= 0
            ? (repay
                ? 'Bạn không còn khoản vay nào với đối tượng này.'
                : 'Đối tượng này không còn khoản nợ cần thu.')
            : (repay
                ? 'Số tiền trả nợ vượt số còn phải trả.'
                : 'Số tiền thu nợ vượt số còn phải thu.'));
      }
    }
  }

  /// Gắn hoặc bỏ ảnh hóa đơn (chỉ lưu trên thiết bị).
  void setPhoto(String entryId, String? path) {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i < 0) return;
    _entries[i] = _entries[i].copyWith(photo: path, clearPhoto: path == null);
    _changed(sync: false);
  }

  // ---------------------------------------------------------------- định kỳ
  void saveRecurring(RecurringRule r) {
    _validateEntry(
        MoneyEntry(
            id: r.id,
            kind: r.kind,
            amount: r.amount,
            walletId: r.walletId,
            date: r.startDate,
            destinationId: r.destinationId,
            categoryId: r.categoryId,
            personId: r.personId,
            note: r.note),
        checkDebt: false);
    if (r.endDate != null &&
        DateUtilsDate.day(r.endDate!).isBefore(DateUtilsDate.day(r.startDate))) {
      throw ArgumentError('Ngày kết thúc phải sau ngày bắt đầu.');
    }
    final i = _recurring.indexWhere((v) => v.id == r.id);
    if (i < 0) {
      _recurring.add(r);
    } else {
      _recurring[i] = r;
    }
    _mark('recurring', r.id);
    recurringError = null;
    _changed();
  }

  void deleteRecurring(String id) {
    _recurring.removeWhere((r) => r.id == id);
    _mark('recurring', id);
    _changed();
  }

  /// Sinh các giao dịch định kỳ đã đến hạn tới thời điểm [now]. Trả về số giao dịch đã tạo.
  int runRecurring({DateTime? now}) {
    final until = now ?? DateTime.now();
    var created = 0;
    for (var i = 0; i < _recurring.length; i++) {
      var rule = _recurring[i];
      if (!rule.active) continue;
      var next = rule.upcoming;
      var guard = 0;
      var changed = false;
      while (!next.isAfter(until) && guard++ < 400) {
        if (rule.endDate != null &&
            DateUtilsDate.day(next).isAfter(DateUtilsDate.day(rule.endDate!))) {
          break;
        }
        final id = rule.occurrenceId(next);
        if (!_entries.any((e) => e.id == id)) {
          try {
            saveEntry(MoneyEntry(
                id: id,
                kind: rule.kind,
                amount: rule.amount,
                walletId: rule.walletId,
                date: next,
                destinationId: rule.destinationId,
                categoryId: rule.categoryId,
                personId: rule.personId,
                note: rule.note,
                recurringId: rule.id));
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
      if (rule.active &&
          rule.endDate != null &&
          DateUtilsDate.day(next).isAfter(DateUtilsDate.day(rule.endDate!))) {
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

  void deleteEntry(String id) {
    _entries.removeWhere((e) => e.id == id);
    _mark('entries', id);
    _changed();
  }

  // ---------------------------------------------------------------- danh mục
  void saveCategory(MoneyCategory c) {
    if (c.name.trim().isEmpty) {
      throw ArgumentError('Vui lòng nhập tên danh mục.');
    }
    if (_categories.any((v) =>
        v.id != c.id &&
        v.income == c.income &&
        v.name.trim().toLowerCase() == c.name.trim().toLowerCase())) {
      throw ArgumentError('Tên danh mục đã tồn tại.');
    }
    final i = _categories.indexWhere((v) => v.id == c.id);
    if (i < 0) {
      _categories.add(c);
    } else {
      _categories[i] = c;
    }
    _mark('categories', c.id);
    _changed();
  }

  void deleteCategory(String id) {
    if (_entries.any((e) => e.categoryId == id) ||
        _budgets.any((b) => b.categoryId == id) ||
        _recurring.any((r) => r.categoryId == id)) {
      throw ArgumentError('Danh mục đang được sử dụng.');
    }
    _categories.removeWhere((c) => c.id == id);
    _mark('categories', id);
    _changed();
  }

  // ---------------------------------------------------------------- đối tượng
  void savePerson(MoneyPerson p) {
    if (p.name.trim().isEmpty) {
      throw ArgumentError('Vui lòng nhập tên đối tượng.');
    }
    final i = _people.indexWhere((v) => v.id == p.id);
    if (i < 0) {
      _people.add(p);
    } else {
      _people[i] = p;
    }
    _mark('people', p.id);
    _changed();
  }

  void deletePerson(String id) {
    if (_entries.any((e) => e.personId == id) ||
        _recurring.any((r) => r.personId == id)) {
      throw ArgumentError('Đối tượng đang có giao dịch.');
    }
    _people.removeWhere((p) => p.id == id);
    _mark('people', id);
    _changed();
  }

  // ---------------------------------------------------------------- ngân sách
  void saveBudget(MoneyBudget b) {
    if (!b.amount.isFinite ||
        b.amount <= 0 ||
        (b.categoryId != null && category(b.categoryId) == null)) {
      throw ArgumentError('Nhập mục tiêu lớn hơn 0 và chọn danh mục.');
    }
    if (b.walletId != null &&
        (findWallet(b.walletId) == null ||
            wallet(b.walletId!).currency != b.currency)) {
      throw ArgumentError('Tiền tệ không khớp với ví.');
    }
    if (_budgets.any((v) =>
        v.id != b.id &&
        v.categoryId == b.categoryId &&
        budgetIncome(v) == budgetIncome(b) &&
        (v.walletId == b.walletId ||
            v.walletId == null ||
            b.walletId == null) &&
        v.currency == b.currency &&
        v.month.year == b.month.year &&
        v.month.month == b.month.month)) {
      throw ArgumentError(b.categoryId == null
          ? 'Mục tiêu tổng của tháng này đã tồn tại.'
          : 'Mục tiêu cho danh mục và ví trong tháng này đã tồn tại.');
    }
    final i = _budgets.indexWhere((v) => v.id == b.id);
    if (i < 0) {
      _budgets.add(b);
    } else {
      _budgets[i] = b;
    }
    _mark('budgets', b.id);
    _changed();
  }

  void deleteBudget(String id) {
    _budgets.removeWhere((b) => b.id == id);
    _mark('budgets', id);
    _changed();
  }

  /// Sao chép ngân sách tháng [from] sang tháng [to]; bỏ qua mục đã có.
  int copyBudgets(DateTime from, DateTime to, {String? unit}) {
    var count = 0;
    for (final b in _budgets
        .where((b) =>
            b.month.year == from.year &&
            b.month.month == from.month &&
            b.currency == (unit ?? currency))
        .toList()) {
      try {
        saveBudget(MoneyBudget(
            id: newId(),
            categoryId: b.categoryId,
            month: DateTime(to.year, to.month),
            amount: b.amount,
            walletId: b.walletId,
            currency: b.currency,
            income: b.income));
        count++;
      } on ArgumentError {
        // đã có ngân sách tương ứng ở tháng đích
      }
    }
    return count;
  }

  void preferences({String? name, String? unit, bool? hidden}) {
    if (name != null && name.trim().isNotEmpty) displayName = name.trim();
    currency = unit ?? currency;
    hideBalance = hidden ?? hideBalance;
    if (session != null) _profileDirty = true;
    _changed();
  }

  String exportCsv() {
    String quote(Object? s) =>
        '"${(s ?? '').toString().replaceAll('"', '""')}"';
    return '﻿${[
      [
        'Ngày',
        'Loại',
        'Số tiền',
        'Tiền tệ',
        'Ví',
        'Ví nhận',
        'Danh mục',
        'Đối tượng',
        'Ghi chú'
      ],
      ..._entries.map((e) => [
            e.date.toIso8601String(),
            e.kind.label,
            e.amount,
            findWallet(e.walletId)?.currency ?? '',
            findWallet(e.walletId)?.name ?? '',
            findWallet(e.destinationId)?.name ?? '',
            category(e.categoryId)?.name ?? '',
            personName(e.personId),
            e.note
          ])
    ].map((row) => row.map(quote).join(',')).join('\r\n')}';
  }

  // ================================================================ tài khoản
  /// Gọi API; khi access token hết hạn (401) tự xin token mới bằng refresh token rồi gọi lại.
  Future<Map<String, dynamic>> _call(String method, String path,
      {Object? body, bool auth = true}) async {
    try {
      return await api.send(method, session?.baseUrl ?? serverUrl, path,
          body: body, token: auth ? session?.token : null);
    } on ApiException catch (e) {
      final current = session;
      if (!auth ||
          !e.isUnauthorized ||
          current == null ||
          current.refreshToken == null) {
        rethrow;
      }
      final Map<String, dynamic> r;
      try {
        r = await api.send('POST', current.baseUrl, '/auth/refresh',
            body: {'refreshToken': current.refreshToken});
      } on ApiException {
        throw e;
      }
      session = current.withToken(r['token'] as String,
          refresh: r['refreshToken'] as String?);
      _changed(sync: false);
      return api.send(method, current.baseUrl, path,
          body: body, token: session!.token);
    }
  }

  void setServerUrl(String url) {
    serverUrl = ApiClient.normalize(url);
    _storage?.setString(serverKey, serverUrl);
    _notify();
  }

  /// Kiểm tra kết nối tới backend; trả về null nếu thành công, ngược lại là thông báo lỗi.
  Future<String?> checkServer([String? url]) async {
    try {
      final r = await api.send('GET', url ?? serverUrl, '/health');
      return r['status'] == 'ok' ? null : 'Máy chủ không phản hồi đúng.';
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Đăng nhập. Trả về true nếu cả máy này và tài khoản đều có dữ liệu,
  /// khi đó giao diện cần gọi [resolveLogin] để người dùng chọn cách xử lý.
  Future<bool> signIn({required String email, required String password}) async {
    final r = await _call('POST', '/auth/login',
        body: {'email': email.trim(), 'password': password}, auth: false);
    return _startSession(r);
  }

  Future<bool> register(
      {required String name,
      required String email,
      required String password}) async {
    final r = await _call('POST', '/auth/register',
        body: {'name': name.trim(), 'email': email.trim(), 'password': password},
        auth: false);
    return _startSession(r);
  }

  /// Gửi mã khôi phục qua email. Trả về mã thử nghiệm nếu máy chủ chạy ở
  /// chế độ phát triển chưa cấu hình email.
  Future<String?> forgotPassword(String email) async {
    final r = await _call('POST', '/auth/forgot-password',
        body: {'email': email.trim()}, auth: false);
    return r['devCode'] as String?;
  }

  Future<bool> resetPassword(
      {required String email,
      required String code,
      required String newPassword}) async {
    final r = await _call('POST', '/auth/reset-password',
        body: {
          'email': email.trim(),
          'code': code.trim(),
          'newPassword': newPassword
        },
        auth: false);
    return _startSession(r);
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final r = await _call('PUT', '/auth/change-password',
        body: {'oldPassword': oldPassword, 'newPassword': newPassword});
    session = session!.withToken(r['token'] as String,
        refresh: r['refreshToken'] as String?);
    syncError = null;
    _changed(sync: false);
  }

  /// Xác thực email bằng mã 6 số đã gửi khi đăng ký.
  Future<void> verifyEmail(String code) async {
    await _call('POST', '/auth/verify-email', body: {'code': code.trim()});
    session = session!.withToken(session!.token, verified: true);
    _changed(sync: false);
  }

  /// Gửi lại mã xác thực; trả về mã thử nghiệm nếu máy chủ chưa cấu hình email.
  Future<String?> resendVerification() async {
    final r = await _call('POST', '/auth/resend-verification');
    return r['devCode'] as String?;
  }

  /// Hỏi trợ lý AI ở backend (mô hình ngôn ngữ). Trả về null nếu không gọi được.
  Future<({String reply, String source})?> askServerAssistant(
      List<Map<String, String>> messages) async {
    if (session == null) return null;
    try {
      final r = await _call('POST', '/ai/chat', body: {'messages': messages});
      return (reply: '${r['reply']}', source: '${r['source'] ?? 'server'}');
    } on ApiException {
      return null;
    }
  }

  /// Gọi API AI ở backend. Trước đó đẩy các thay đổi đang chờ để máy chủ
  /// phân tích trên dữ liệu mới nhất. Ném [ApiException] nếu chưa đăng nhập.
  Future<Map<String, dynamic>> aiRequest(String method, String path,
      {Object? body, bool pushFirst = true}) async {
    if (session == null) {
      throw const ApiException(0, 'OFFLINE', 'Cần đăng nhập để dùng AI máy chủ.');
    }
    if (pushFirst && pendingChanges > 0) await syncNow(pull: false);
    return _call(method, '/ai$path', body: body);
  }

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
    final Map<String, dynamic> snapshot;
    try {
      snapshot = await _call('GET', '/sync');
    } catch (_) {
      session = null;
      rethrow;
    }
    if (_hasData(snapshot)) {
      if (_localHasData) {
        // Chưa lưu phiên cho tới khi người dùng chọn cách xử lý dữ liệu.
        _pendingSnapshot = snapshot;
        _notify();
        return true;
      }
      _applySnapshot(snapshot);
      return false;
    }
    await _uploadAllLocal();
    return false;
  }

  /// [useAccount] = true: thay dữ liệu máy này bằng dữ liệu tài khoản;
  /// false: gộp dữ liệu máy này lên tài khoản.
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

  static bool _hasData(Map<String, dynamic> s) {
    int n(String k) => (s[k] as List?)?.length ?? 0;
    final wallets = (s['wallets'] as List?) ?? const [];
    return n('entries') > 0 ||
        n('budgets') > 0 ||
        n('people') > 1 ||
        wallets.length > 1 ||
        wallets.any((w) => w is Map && (w['opening'] ?? 0) != 0);
  }

  Future<void> _uploadAllLocal() async {
    for (final w in _wallets) {
      _mark('wallets', w.id);
    }
    for (final c in _categories) {
      _mark('categories', c.id);
    }
    for (final p in _people) {
      _mark('people', p.id);
    }
    for (final e in _entries) {
      _mark('entries', e.id);
    }
    for (final b in _budgets) {
      _mark('budgets', b.id);
    }
    for (final r in _recurring) {
      _mark('recurring', r.id);
    }
    _changed(sync: false);
    await syncNow();
  }

  void _applySnapshot(Map<String, dynamic> s) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        ((s[key] as List?) ?? const [])
            .map((v) => parse(Map<String, dynamic>.from(v as Map)))
            .toList();
    _wallets = list('wallets', MoneyWallet.fromJson);
    _categories = list('categories', MoneyCategory.fromJson);
    _people = list('people', MoneyPerson.fromJson);
    // Ảnh hóa đơn chỉ nằm trên thiết bị nên được giữ lại khi tải dữ liệu mới.
    final photos = {
      for (final e in _entries)
        if (e.photo != null) e.id: e.photo!
    };
    _entries = [
      for (final e in list('entries', MoneyEntry.fromJson))
        photos[e.id] == null ? e : e.copyWith(photo: photos[e.id])
    ];
    _budgets = list('budgets', MoneyBudget.fromJson);
    _recurring = list('recurring', RecurringRule.fromJson);
    final user = s['user'];
    if (user is Map) {
      displayName = '${user['name'] ?? displayName}';
      currency = '${user['currency'] ?? currency}';
      hideBalance = user['hideBalance'] == true;
      if (user['rates'] is Map) rates = _readRates(user['rates']);
      final current = session;
      if (current != null && user['emailVerified'] != null) {
        session = current.withToken(current.token,
            verified: user['emailVerified'] != false);
      }
    }
    _dirty.clear();
    _profileDirty = false;
    lastSync = DateTime.now();
    syncError = null;
    _changed(sync: false);
    runRecurring();
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer =
        Timer(const Duration(milliseconds: 800), () => syncNow(pull: false));
  }

  /// Gửi các thay đổi đang chờ, sau đó (nếu [pull]) tải lại dữ liệu mới nhất.
  Future<void> syncNow({bool pull = true}) async {
    if (session == null || syncing) return;
    syncing = true;
    _notify();
    try {
      await _push();
      if (pull && _dirty.isEmpty && !_profileDirty) {
        final snapshot = await _call('GET', '/sync');
        if (_dirty.isEmpty && !_profileDirty) _applySnapshot(snapshot);
      }
      lastSync = DateTime.now();
      syncError = null;
    } on ApiException catch (e) {
      syncError = e.isUnauthorized
          ? 'Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất và đăng nhập lại.'
          : e.message;
    } finally {
      syncing = false;
      _changed(sync: false);
    }
  }

  static const _upsertOrder = [
    'wallets',
    'categories',
    'people',
    'recurring',
    'entries',
    'budgets'
  ];

  Map<String, dynamic>? _json(String entity, String id) {
    Iterable<dynamic> list = switch (entity) {
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

  Future<void> _push() async {
    if (_profileDirty) {
      _profileDirty = false;
      try {
        await _call('PUT', '/auth/me', body: {
          'name': displayName,
          'currency': currency,
          'hideBalance': hideBalance,
          'rates': rates
        });
      } catch (_) {
        _profileDirty = true;
        rethrow;
      }
    }
    if (_dirty.isEmpty) return;
    final snapshot = Map.of(_dirty);
    final upserts = <String, List<Map<String, dynamic>>>{};
    final deletes = <String, List<Map<String, dynamic>>>{};
    for (final key in snapshot.keys) {
      final i = key.indexOf(':');
      final entity = key.substring(0, i), id = key.substring(i + 1);
      final data = _json(entity, id);
      final op = {
        'entity': entity,
        'action': data == null ? 'delete' : 'upsert',
        'id': id,
        if (data != null) 'data': data,
        '_key': key
      };
      (data == null ? deletes : upserts).putIfAbsent(entity, () => []).add(op);
    }
    // Xóa giao dịch/ngân sách trước, rồi ghi ví → danh mục → đối tượng → giao dịch → ngân sách,
    // cuối cùng xóa đối tượng/danh mục/ví để không vi phạm ràng buộc tham chiếu.
    final ops = [
      ...?deletes['budgets'],
      ...?deletes['entries'],
      ...?deletes['recurring'],
      for (final e in _upsertOrder) ...?upserts[e],
      ...?deletes['people'],
      ...?deletes['categories'],
      ...?deletes['wallets'],
    ];
    void done(int count) {
      for (final op in ops.take(count)) {
        final key = op['_key'] as String;
        if (_dirty[key] == snapshot[key]) _dirty.remove(key);
      }
    }

    try {
      await _call('POST', '/sync/batch', body: {
        'ops': [
          for (final op in ops) Map.of(op)..remove('_key'),
        ]
      });
      done(ops.length);
    } on ApiException catch (e) {
      final applied = e.body?['applied'];
      if (applied is int) {
        done(applied);
        throw ApiException(
            e.status, e.code, 'Chưa đồng bộ được một thay đổi: ${e.message}');
      }
      rethrow;
    }
  }

  /// Bỏ các thay đổi chưa đồng bộ và tải lại dữ liệu từ tài khoản.
  Future<void> discardLocalChanges() async {
    if (session == null) return;
    _dirty.clear();
    _profileDirty = false;
    await syncNow();
  }

  /// Đăng xuất: thu hồi token trên máy chủ và xóa dữ liệu khỏi thiết bị.
  Future<void> signOut({bool revoke = true}) async {
    _syncTimer?.cancel();
    if (revoke && session != null) {
      try {
        await _call('POST', '/auth/logout');
      } catch (_) {
        // Máy chủ không truy cập được: vẫn xóa phiên trên thiết bị.
      }
    }
    session = null;
    _pendingSnapshot = null;
    _dirty.clear();
    _profileDirty = false;
    lastSync = null;
    syncError = null;
    _resetData();
    await _pendingSave;
    await _storage?.remove(storageKey);
    _notify();
  }

  Future<void> deleteAccount(String password) async {
    await _call('DELETE', '/auth/me', body: {'password': password});
    await signOut(revoke: false);
  }
}

class DateUtilsDate {
  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
}
