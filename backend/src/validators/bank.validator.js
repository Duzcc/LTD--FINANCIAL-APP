const { badRequest } = require('../utils/errors');

const MAX_QR_AMOUNT = 500000000;

function optionalAmount(value) {
  if (value === undefined || value === null || value === '') return null;
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) throw badRequest('Số tiền phải lớn hơn 0.');
  if (!Number.isInteger(amount)) throw badRequest('Số tiền VND phải là số nguyên.');
  if (amount > MAX_QR_AMOUNT) throw badRequest('Số tiền tối đa 500.000.000 đ mỗi mã QR.');
  return amount;
}

const paymentRequest = (body) => ({
  walletId: String(body.walletId || ''),
  kind: body.kind === 'collect' ? 'collect' : 'income',
  amount: optionalAmount(body.amount),
  personId: body.personId ? String(body.personId) : null,
  categoryId: body.categoryId ? String(body.categoryId) : null,
  note: String(body.note || '')
    .trim()
    .slice(0, 100),
});

function webhookTransfer(body = {}) {
  if (body.id === undefined || body.id === null) throw badRequest('Thiếu mã giao dịch SePay.');
  return body;
}

module.exports = { paymentRequest, webhookTransfer };
