// Quy ước dùng chung giữa backend và ứng dụng Flutter (lib/models/finance_models.dart).
const KINDS = {
  expense: { label: 'Chi tiêu', sign: -1 },
  income: { label: 'Thu nhập', sign: 1 },
  transfer: { label: 'Chuyển tiền', sign: -1 },
  lend: { label: 'Cho vay', sign: -1 },
  collect: { label: 'Thu nợ', sign: 1 },
  interestIncome: { label: 'Thu lãi', sign: 1 },
  borrow: { label: 'Đi vay', sign: 1 },
  repay: { label: 'Trả nợ', sign: -1 },
  interestExpense: { label: 'Trả lãi', sign: -1 },
};
const DEBT_KINDS = ['lend', 'collect', 'interestIncome', 'borrow', 'repay', 'interestExpense'];
const isDebt = (k) => DEBT_KINDS.includes(k);
const isIncome = (k) => k === 'income' || k === 'interestIncome';
const isExpense = (k) => k === 'expense' || k === 'interestExpense';
const CURRENCIES = ['VND', 'USD', 'EUR', 'GBP', 'JPY', 'CNY'];
const CATEGORY_SYMBOLS = 24; // số biểu tượng danh mục ở client

module.exports = { KINDS, DEBT_KINDS, isDebt, isIncome, isExpense, CURRENCIES, CATEGORY_SYMBOLS };
