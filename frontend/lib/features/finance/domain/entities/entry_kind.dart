enum EntryKind {
  expense('Chi tiêu', -1),
  income('Thu nhập', 1),
  transfer('Chuyển tiền', -1),
  lend('Cho vay', -1),
  collect('Thu nợ', 1),
  interestIncome('Thu lãi', 1),
  borrow('Đi vay', 1),
  repay('Trả nợ', -1),
  interestExpense('Trả lãi', -1);

  const EntryKind(this.label, this.sign);
  final String label;
  final int sign;
  bool get isDebt => index >= 3;
  bool get isIncome => this == income || this == interestIncome;
  bool get isExpense => this == expense || this == interestExpense;
}
