const crypto = require('crypto');
const config = require('../config');
const ledger = require('./ledger.service');
const sepay = require('./sepay.service');
const users = require('../repositories/user.repository');
const requests = require('../repositories/payment-request.repository');
const L = require('../domain/ledger');
const validate = require('../validators/bank.validator');
const { sha256, randomToken } = require('../utils/crypto');
const { parseVnDateTime } = require('../utils/time');
const { badRequest, conflict, notFound, unauthorized } = require('../utils/errors');

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_ATTEMPTS = 5;

const newCode = () => `LTD${Array.from({ length: 6 }, () => CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)]).join('')}`;

const sepayStatus = (user, webhookUrl) => ({
  connected: Boolean(user.sepayKeyHash),
  keyHint: user.sepayKeyHint,
  pollingEnabled: sepay.pollingEnabled(),
  pollSeconds: config.sepay.pollSeconds,
  webhookUrl,
});

async function createWebhookKey(user, webhookUrl) {
  const apiKey = `ltd_${randomToken(24)}`;
  user.sepayKeyHash = sha256(apiKey);
  user.sepayKeyHint = apiKey.slice(-4);
  await users.save(user);
  return { apiKey, keyHint: user.sepayKeyHint, webhookUrl };
}

async function revokeWebhookKey(user) {
  user.sepayKeyHash = null;
  user.sepayKeyHint = null;
  await users.save(user);
}

async function listRequests(user, query) {
  const items = await requests.listForUser(user._id, { walletId: query.walletId && String(query.walletId) });
  return { items: items.map((r) => r.toJSON()) };
}

async function findRequest(user, id) {
  const request = await requests.findForUser(id, user._id);
  if (!request) throw notFound();
  return request;
}

async function getRequest(user, id) {
  const request = await findRequest(user, id);
  if (request.status === 'pending' && (await sepay.syncSoon())) return (await requests.findById(request._id)).toJSON();
  return request.toJSON();
}

function checkCollect(state, { personId, amount }) {
  if (!personId || !L.byId(state.people, personId)) throw badRequest('Chọn người cần thu nợ.');
  const owed = L.outstanding(state, { borrowed: false, personId, currency: 'VND' });
  if (owed <= 0) throw badRequest('Người này không còn khoản nợ cần thu.');
  if (!amount) throw badRequest('Nhập số tiền cần thu.');
  if (amount > owed) throw badRequest(`Số tiền thu nợ vượt số còn phải thu (${owed}).`);
}

function checkIncomeCategory(state, categoryId) {
  if (!categoryId) return;
  if (!L.byId(state.categories, categoryId)?.income) throw badRequest('Chọn danh mục thu nhập phù hợp.');
}

// Mã ngẫu nhiên hiếm khi trùng mã đã có; nếu trùng thì tạo mã khác và thử lại.
async function insertWithUniqueCode(data) {
  for (let attempt = 1; attempt <= CODE_ATTEMPTS; attempt += 1) {
    const request = await requests.createUnique({ ...data, code: newCode() });
    if (request) return request;
  }
  throw conflict('Không tạo được mã thanh toán, vui lòng thử lại.', 'DUPLICATE');
}

async function createRequest(user, body) {
  const input = validate.paymentRequest(body);
  const state = await ledger.loadState(user._id);
  const wallet = L.byId(state.wallets, input.walletId);
  if (!wallet) throw badRequest('Vui lòng chọn ví hợp lệ.');
  if (!wallet.bankBin || !wallet.bankAccount) throw badRequest('Ví chưa liên kết tài khoản ngân hàng.');
  if (input.kind === 'collect') checkCollect(state, input);
  else checkIncomeCategory(state, input.categoryId);
  const request = await insertWithUniqueCode({
    ...input,
    user: user._id,
    walletId: wallet.id,
    categoryId: input.kind === 'collect' ? null : input.categoryId,
    expiresAt: new Date(Date.now() + config.paymentRequestDays * 86400000),
  });
  return request.toJSON();
}

async function cancelRequest(user, id) {
  const request = await findRequest(user, id);
  if (request.status === 'paid') throw badRequest('Yêu cầu đã được thanh toán, không thể hủy.');
  request.status = 'cancelled';
  await requests.save(request);
  return request.toJSON();
}

async function handleWebhook(authorization, body) {
  const [scheme, key] = String(authorization || '').split(' ');
  const user = /^apikey$/i.test(scheme || '') && key ? await users.findBySepayKeyHash(sha256(key.trim())) : null;
  if (!user) throw unauthorized('API key webhook không hợp lệ.');
  const transfer = validate.webhookTransfer(body);
  return sepay.handleIncoming({
    userId: user._id,
    providerId: transfer.id,
    accountNumber: transfer.accountNumber,
    transferType: transfer.transferType === 'out' ? 'out' : 'in',
    amount: Number(transfer.transferAmount),
    text: `${transfer.code || ''} ${transfer.content || ''} ${transfer.description || ''}`,
    occurredAt: parseVnDateTime(transfer.transactionDate),
  });
}

module.exports = {
  sepayStatus, createWebhookKey, revokeWebhookKey, listRequests, getRequest, createRequest, cancelRequest, handleWebhook,
};
