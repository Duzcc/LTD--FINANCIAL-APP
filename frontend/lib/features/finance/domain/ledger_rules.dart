import 'package:finance_app/core/utils/dates.dart';
import 'package:finance_app/core/validation/validators.dart';
import 'package:finance_app/features/finance/domain/entities/entities.dart';
import 'package:finance_app/features/finance/domain/ledger_queries.dart';

mixin LedgerRules on LedgerQueries {
  bool _sameName(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  void checkWallet(MoneyWallet value) {
    if (value.name.trim().isEmpty ||
        !value.opening.isFinite ||
        value.opening < 0 ||
        !value.target.isFinite ||
        value.target < 0) {
      throw ArgumentError('Nhập tên ví và số tiền hợp lệ, không âm.');
    }
    if (wallets.any((w) => w.id != value.id && _sameName(w.name, value.name))) {
      throw ArgumentError('Tên ví đã tồn tại. Vui lòng đặt tên khác.');
    }
    if (value.startDate != null &&
        value.deadline != null &&
        dateOnly(value.deadline!).isBefore(dateOnly(value.startDate!))) {
      throw ArgumentError('Ngày kết thúc phải sau ngày bắt đầu.');
    }
    _checkBankLink(value);
    final current = findWallet(value.id);
    if (current != null && current.currency != value.currency && walletReferences(value.id) > 0) {
      throw ArgumentError('Ví đã có giao dịch hoặc ngân sách nên không thể đổi tiền tệ.');
    }
  }

  void _checkBankLink(MoneyWallet value) {
    final fields = [value.bankBin, value.bankAccount, value.bankHolder];
    if (fields.every((f) => f == null)) return;
    final error = fields.contains(null)
        ? 'Nhập đủ ngân hàng, số tài khoản và tên chủ tài khoản.'
        : value.currency != 'VND'
            ? 'Chỉ liên kết ngân hàng cho ví VND.'
            : validateBankAccount(value.bankAccount) ?? validateBankHolder(value.bankHolder);
    if (error != null) throw ArgumentError(error);
  }

  void checkWalletRemovable(String id, {required bool cascade}) {
    if (!cascade && walletReferences(id) > 0) {
      throw ArgumentError('Ví đang có giao dịch hoặc ngân sách. Hãy xử lý các dữ liệu liên quan trước.');
    }
  }

  void checkEntry(MoneyEntry value, {bool checkDebt = true, bool checkBalance = true}) {
    if (!value.amount.isFinite || value.amount <= 0) throw ArgumentError('Số tiền phải lớn hơn 0.');
    final source = findWallet(value.walletId);
    if (source == null) throw ArgumentError('Vui lòng chọn ví hợp lệ.');
    if (value.kind == EntryKind.transfer) _checkTransfer(value, source, checkBalance: checkBalance);
    if (value.kind.isExpense || value.kind.isIncome) {
      final c = category(value.categoryId);
      if (c == null || c.income != value.kind.isIncome) {
        throw ArgumentError('Chọn danh mục phù hợp với giao dịch.');
      }
    }
    if (value.kind.isDebt && personName(value.personId).isEmpty) {
      throw ArgumentError('Chọn đối tượng cho giao dịch vay/nợ.');
    }
    if (value.dueDate != null && dateOnly(value.dueDate!).isBefore(dateOnly(value.date))) {
      throw ArgumentError('Ngày đến hạn không được trước ngày giao dịch.');
    }
    if (checkDebt && (value.kind == EntryKind.collect || value.kind == EntryKind.repay)) {
      _checkSettlement(value, source);
    }
  }

  void _checkTransfer(MoneyEntry value, MoneyWallet source, {required bool checkBalance}) {
    final destination = findWallet(value.destinationId);
    if (destination == null || destination.id == source.id) throw ArgumentError('Chọn hai ví khác nhau.');
    if (destination.currency != source.currency) throw ArgumentError('Chỉ chuyển giữa hai ví cùng tiền tệ.');
    if (!checkBalance) return;
    final previous = entries.where((e) => e.id == value.id).firstOrNull;
    final available = balance(source.id) - (previous == null ? 0 : _effectOn(previous, source.id));
    if (value.amount > available + 1e-9) {
      throw ArgumentError('Số dư ví ${source.name} không đủ (còn ${_amount(available)} ${source.currency}).');
    }
  }

  double _effectOn(MoneyEntry e, String walletId) =>
      (e.walletId == walletId ? e.amount * e.kind.sign : 0) +
      (e.kind == EntryKind.transfer && e.destinationId == walletId ? e.amount : 0);

  String _amount(double v) {
    final digits = v.abs().round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
    return v < 0 ? '-$digits' : digits;
  }

  void _checkSettlement(MoneyEntry value, MoneyWallet source) {
    final repay = value.kind == EntryKind.repay;
    final left = debt(borrowed: repay, personId: value.personId, unit: source.currency, excludeId: value.id);
    if (value.amount <= left + 1e-9) return;
    if (left <= 0) {
      throw ArgumentError(
          repay ? 'Bạn không còn khoản vay nào với đối tượng này.' : 'Đối tượng này không còn khoản nợ cần thu.');
    }
    throw ArgumentError(repay ? 'Số tiền trả nợ vượt số còn phải trả.' : 'Số tiền thu nợ vượt số còn phải thu.');
  }

  void checkRecurring(RecurringRule r) {
    checkEntry(
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
        checkDebt: false,
        checkBalance: false);
    if (r.endDate != null && dateOnly(r.endDate!).isBefore(dateOnly(r.startDate))) {
      throw ArgumentError('Ngày kết thúc phải sau ngày bắt đầu.');
    }
  }

  void checkCategory(MoneyCategory c) {
    if (c.name.trim().isEmpty) throw ArgumentError('Vui lòng nhập tên danh mục.');
    if (categories.any((v) => v.id != c.id && v.income == c.income && _sameName(v.name, c.name))) {
      throw ArgumentError('Tên danh mục đã tồn tại.');
    }
  }

  void checkCategoryRemovable(String id) {
    if (entries.any((e) => e.categoryId == id) ||
        budgets.any((b) => b.categoryId == id) ||
        recurring.any((r) => r.categoryId == id)) {
      throw ArgumentError('Danh mục đang được sử dụng.');
    }
  }

  void checkPerson(MoneyPerson p) {
    if (p.name.trim().isEmpty) throw ArgumentError('Vui lòng nhập tên đối tượng.');
  }

  void checkPersonRemovable(String id) {
    if (entries.any((e) => e.personId == id) || recurring.any((r) => r.personId == id)) {
      throw ArgumentError('Đối tượng đang có giao dịch.');
    }
  }

  void checkBudget(MoneyBudget b) {
    final error = budgetError(b);
    if (error != null) throw ArgumentError(error);
  }

  String? budgetError(MoneyBudget b) {
    if (!b.amount.isFinite || b.amount <= 0 || (b.categoryId != null && category(b.categoryId) == null)) {
      return 'Nhập mục tiêu lớn hơn 0 và chọn danh mục.';
    }
    if (b.walletId != null && findWallet(b.walletId)?.currency != b.currency) {
      return 'Tiền tệ không khớp với ví.';
    }
    final overlaps = budgets.any((v) =>
        v.id != b.id &&
        v.categoryId == b.categoryId &&
        budgetIncome(v) == budgetIncome(b) &&
        (v.walletId == b.walletId || v.walletId == null || b.walletId == null) &&
        v.currency == b.currency &&
        v.month.year == b.month.year &&
        v.month.month == b.month.month);
    if (!overlaps) return null;
    return b.categoryId == null
        ? 'Mục tiêu tổng của tháng này đã tồn tại.'
        : 'Mục tiêu cho danh mục và ví trong tháng này đã tồn tại.';
  }
}
