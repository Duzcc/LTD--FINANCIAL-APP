const config = require('../config');
const ledger = require('./ledger.service');
const requests = require('../repositories/payment-request.repository');
const events = require('../repositories/bank-event.repository');
const users = require('../repositories/user.repository');
const ledgerRepository = require('../repositories/ledger.repository');
const sepayClient = require('../integrations/sepay.client');
const L = require('../domain/ledger');
const { KINDS } = require('../domain/constants');
const { badRequest } = require('../utils/errors');
const { formatVnDateTime, parseVnDateTime } = require('../utils/time');

const LOOKBACK_MS = 3600000;
const SAME_TRANSFER_MS = 86400000;
const PAGE_SIZE = 5000;

// ngân hàng hay chèn dấu cách vào nội dung nên bỏ hết ký tự lạ rồi mới tìm mã LTD
const findCodes = (text) => [...String(text || '').toUpperCase().replace(/[^A-Z0-9]/g, '')
  .matchAll(/(?=(LTD[A-HJ-NP-Z2-9]{6}))/g)].map((m) => m[1]);

function incomeCategory(state, request) {
  const category = (request.categoryId && L.byId(state.categories, request.categoryId))
    || state.categories.find((c) => c.income && c.id === 'other_income')
    || state.categories.find((c) => c.income);
  if (!category) throw badRequest('Chưa có danh mục thu nhập.');
  return category;
}

async function recordPayment(userId, state, request, event) {
  const id = bankEntryId(event);
  const label = request.note || (request.kind === 'collect' ? 'Thu nợ qua VietQR' : 'Nhận tiền qua VietQR');
  const note = [label, request.code].filter(Boolean).join(' • ');
  const base = { amount: event.amount, walletId: request.walletId, date: event.occurredAt || new Date(), note };
  const income = { ...base, kind: 'income', categoryId: incomeCategory(state, request).id, personId: request.personId };
  let entry = income;
  if (request.kind === 'collect') {
    const owed = L.outstanding(state, { borrowed: false, personId: request.personId, currency: 'VND' });
    entry = event.amount <= owed
      ? { ...base, kind: 'collect', personId: request.personId }
      : { ...income, note: `${note} (vượt số nợ còn lại)` };
  }
  await ledger.upsert(userId, state, 'entries', id, entry);
  return id;
}

const bankEntryId = (event) => `bank_${event.providerId}`.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);

function expenseCategory(state) {
  const expense = state.categories.filter((c) => !c.income);
  const category = expense.find((c) => /khác/i.test(c.name)) || expense.find((c) => c.id === 'life') || expense[0];
  if (!category) throw badRequest('Chưa có danh mục chi tiêu.');
  return category;
}

function linkedWallet(state, accountNumber) {
  return accountNumber ? state.wallets.find((w) => w.bankAccount === accountNumber) : null;
}

function direction(entry, walletId) {
  if (entry.kind === 'transfer') return entry.destinationId === walletId ? 'in' : entry.walletId === walletId ? 'out' : null;
  if (entry.walletId !== walletId) return null;
  return KINDS[entry.kind].sign > 0 ? 'in' : 'out';
}

// người dùng có thể đã tự ghi rồi: cùng số tiền, cùng chiều, lệch không quá 1 ngày thì coi là một
async function manualTwin(owner, state, wallet, event) {
  const at = (event.occurredAt || new Date()).getTime();
  const taken = new Set(await events.linkedEntryIds(owner));
  return state.entries.find((e) => !e.id.startsWith('bank_')
    && !taken.has(e.id)
    && e.amount === event.amount
    && direction(e, wallet.id) === event.transferType
    && Math.abs(new Date(e.date).getTime() - at) <= SAME_TRANSFER_MS);
}

async function recordBankTransfer(owner, state, wallet, event, text) {
  const inbound = event.transferType === 'in';
  const content = String(text).replace(/\s+/g, ' ').trim().slice(0, 200);
  const entry = {
    kind: inbound ? 'income' : 'expense',
    amount: event.amount,
    walletId: wallet.id,
    categoryId: inbound ? incomeCategory(state, {}).id : expenseCategory(state).id,
    date: event.occurredAt || new Date(),
    note: `${inbound ? 'Nhận chuyển khoản' : 'Chuyển khoản đi'}${content ? ` • ${content}` : ''}`,
  };
  const id = bankEntryId(event);
  await ledger.upsert(owner, state, 'entries', id, entry);
  return id;
}

async function pollingOwner() {
  if (!config.sepay.ownerEmail) return null;
  return (await users.findByEmail(config.sepay.ownerEmail))?._id || null;
}

// SePay có thể gửi lại cùng giao dịch, lần sau trả null để bỏ qua
const createEvent = (owner, { providerId, accountNumber, transferType, amount, text, occurredAt }) => events.createUnique({
  user: owner,
  providerId: String(providerId),
  accountNumber: String(accountNumber || ''),
  transferType: transferType === 'out' ? 'out' : 'in',
  amount: Number.isFinite(amount) ? amount : 0,
  content: String(text).toUpperCase().slice(0, 500),
  occurredAt: occurredAt && !Number.isNaN(occurredAt.getTime()) ? occurredAt : null,
});

function walletMatches(wallet, accountNumber) {
  return Boolean(wallet) && !(accountNumber && wallet.bankAccount && accountNumber !== wallet.bankAccount);
}

async function settle(request, event, entryId) {
  const updated = await requests.addPayment(request._id, { amount: event.amount, paidAt: event.occurredAt || new Date(), entryId });
  if (!updated.amount || updated.paidAmount >= updated.amount) await requests.markPaid(request._id);
}

async function handleIncoming(transfer) {
  const { userId = null, transferType = 'in', amount, text = '' } = transfer;
  const codes = findCodes(text);
  const inbound = transferType === 'in' && amount > 0;
  const request = inbound && codes.length ? await requests.findPendingByCodes(codes, userId) : null;
  const owner = userId || request?.user || (await pollingOwner());
  if (!owner) return { result: inbound ? 'unmatched' : 'ignored' };

  const event = await createEvent(owner, { ...transfer, transferType, text });
  if (!event) return { result: 'duplicate' };
  const finish = async (result, extra = {}) => {
    event.result = result;
    event.entryId = extra.entryId || null;
    await events.save(event);
    return { result, ...extra };
  };
  // ghi lỗi thì xóa sự kiện để lần SePay gửi lại còn xử lý được
  const undoOnError = async (e) => {
    await events.deleteById(event._id);
    throw e;
  };

  const state = await ledger.loadState(owner);
  const live = request && request.expiresAt >= new Date();
  if (live && walletMatches(L.byId(state.wallets, request.walletId), event.accountNumber)) {
    const entryId = await recordPayment(owner, state, request, event).catch(undoOnError);
    await settle(request, event, entryId);
    event.requestId = request._id;
    return finish('matched', { entryId });
  }

  const wallet = linkedWallet(state, event.accountNumber);
  if (!wallet || !(event.amount > 0)) return finish(inbound ? 'unmatched' : 'ignored');
  const twin = await manualTwin(owner, state, wallet, event);
  if (twin) return finish('linked', { entryId: twin.id });
  const entryId = await recordBankTransfer(owner, state, wallet, event, text).catch(undoOnError);
  return finish('recorded', { entryId });
}

const pollingEnabled = () => Boolean(config.sepay.apiToken);
let cursor = 0;
let running = null;
let lastRun = 0;

async function syncStart() {
  const oldest = await requests.findOldestActive();
  const owner = await pollingOwner();
  const wallet = owner ? await ledgerRepository.oldestBankWallet(owner) : null;
  const starts = [oldest && oldest.createdAt.getTime() - LOOKBACK_MS, wallet && wallet.createdAt.getTime()].filter(Boolean);
  return starts.length ? new Date(Math.min(...starts)) : null;
}

// lần đầu lấy từ mốc sớm nhất cần, sau đó chỉ lấy giao dịch mới
async function syncFromApi() {
  if (!pollingEnabled()) return { checked: 0, matched: 0 };
  const start = cursor ? null : await syncStart();
  if (!cursor && !start) return { checked: 0, matched: 0 };
  const params = cursor ? { since_id: cursor + 1 } : { transaction_date_min: formatVnDateTime(start) };
  const list = await sepayClient.listTransactions({ ...params, limit: PAGE_SIZE });
  let matched = 0;
  for (const t of list.sort((a, b) => Number(a.id) - Number(b.id))) {
    const amountIn = Number(t.amount_in) || 0;
    const r = await handleIncoming({
      providerId: t.id,
      accountNumber: t.account_number,
      transferType: amountIn > 0 ? 'in' : 'out',
      amount: amountIn > 0 ? amountIn : Number(t.amount_out) || 0,
      text: `${t.code || ''} ${t.transaction_content || ''}`,
      occurredAt: parseVnDateTime(t.transaction_date),
    });
    if (r.result === 'matched' || r.result === 'recorded') matched += 1;
    cursor = Math.max(cursor, Number(t.id) || 0);
  }
  return { checked: list.length, matched };
}

function syncSoon() {
  if (!pollingEnabled()) return Promise.resolve(0);
  if (running) return running;
  if (Date.now() - lastRun < config.sepay.minGapMs) return Promise.resolve(0);
  lastRun = Date.now();
  running = syncFromApi()
    .then((r) => r.matched)
    .catch((e) => {
      console.warn(`[sepay] không đọc được giao dịch: ${e.message}`);
      return 0;
    })
    .finally(() => { running = null; });
  return running;
}

function startPolling() {
  if (!pollingEnabled()) return;
  console.log(`Đối soát SePay qua User API: mỗi ${config.sepay.pollSeconds} giây khi có mã QR đang chờ`);
  setInterval(syncSoon, config.sepay.pollSeconds * 1000).unref();
}

function resetCursor() {
  cursor = 0;
  lastRun = 0;
}

module.exports = { handleIncoming, syncFromApi, syncSoon, startPolling, pollingEnabled, resetCursor };
