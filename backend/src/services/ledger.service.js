const { Types } = require('mongoose');
const repository = require('../repositories/ledger.repository');
const L = require('../domain/ledger');
const { isDebt, isIncome, isExpense } = require('../domain/constants');
const { notFound, conflict, badRequest } = require('../utils/errors');

const VALIDATORS = {
  wallets: L.validateWallet,
  categories: L.validateCategory,
  people: L.validatePerson,
  entries: L.validateEntry,
  budgets: L.validateBudget,
  recurring: L.validateRecurring,
};
const RESOURCE_KEYS = {
  wallets: 'wallets',
  categories: 'categories',
  people: 'people',
  transactions: 'entries',
  budgets: 'budgets',
  recurring: 'recurring',
};

const isEntity = (key) => Object.hasOwn(VALIDATORS, key);
const newId = () => new Types.ObjectId().toHexString();
const loadState = (userId) => repository.loadState(userId);

function checkId(id) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(id)) throw badRequest('Mã bản ghi không hợp lệ.');
  return id;
}

async function upsert(userId, state, key, id, data, options = {}) {
  const { id: _id, ...fields } = VALIDATORS[key](state, data || {}, checkId(id), options);
  const saved = await repository.upsert(userId, key, id, fields);
  const list = state[key];
  const index = list.findIndex((x) => x.id === id);
  if (index < 0) list.push(saved);
  else list[index] = saved;
  return saved;
}

async function removeWallet(userId, state, id, cascade) {
  const refs = L.walletRefs(state, id);
  if (refs.total === 0) return;
  if (!cascade) {
    throw conflict(
      `Ví đang có ${refs.entries} giao dịch và ${refs.budgets} ngân sách. Gửi cascade=true để xóa kèm dữ liệu liên quan.`,
      'HAS_REFERENCES',
    );
  }
  await repository.removeWalletDependents(userId, id);
  state.entries = state.entries.filter((e) => e.walletId !== id && e.destinationId !== id);
  state.budgets = state.budgets.filter((b) => b.walletId !== id);
  state.recurring = state.recurring.filter((r) => r.walletId !== id && r.destinationId !== id);
}

async function remove(userId, state, key, id, { cascade = false, missingOk = false } = {}) {
  if (!L.byId(state[key], id)) {
    if (missingOk) return;
    throw notFound();
  }
  if (key === 'wallets') await removeWallet(userId, state, id, cascade);
  if (key === 'categories' && L.categoryRefs(state, id) > 0)
    throw conflict('Danh mục đang được sử dụng.', 'HAS_REFERENCES');
  if (key === 'people' && L.personRefs(state, id) > 0) throw conflict('Đối tượng đang có giao dịch.', 'HAS_REFERENCES');
  await repository.remove(userId, key, id);
  state[key] = state[key].filter((x) => x.id !== id);
}

function decorate(key, state, item) {
  if (key === 'wallets') return { ...item, balance: L.balance(state, item.id) };
  if (key === 'budgets') return { ...item, used: L.used(state, item) };
  return item;
}

function matchesType(kind, type) {
  if (type === 'all') return true;
  if (type === 'debt') return isDebt(kind);
  if (type === 'income') return isIncome(kind);
  if (type === 'expense') return isExpense(kind);
  return kind === type;
}

function filterTransactions(state, query) {
  const from = L.date(query.from, 'from');
  const to = L.date(query.to, 'to');
  const text = String(query.q || '')
    .trim()
    .toLowerCase();
  const type = query.type || 'all';
  const nameOf = (list, id) => L.byId(list, id)?.name || '';
  const matches = (e) => {
    const d = new Date(e.date);
    if (from && d < from) return false;
    if (to && d > to) return false;
    if (query.walletId && e.walletId !== query.walletId && e.destinationId !== query.walletId) return false;
    if (query.categoryId && e.categoryId !== query.categoryId) return false;
    if (query.personId && e.personId !== query.personId) return false;
    if (!matchesType(e.kind, type)) return false;
    if (!text) return true;
    return `${nameOf(state.categories, e.categoryId)} ${e.note} ${nameOf(state.people, e.personId)} ${e.amount}`
      .toLowerCase()
      .includes(text);
  };
  const direction = query.order === 'asc' ? 1 : -1;
  const list = state.entries
    .filter(matches)
    .sort((a, b) => direction * (query.sort === 'amount' ? a.amount - b.amount : new Date(a.date) - new Date(b.date)));
  const limit = Math.min(Math.max(Number(query.limit) || 500, 1), 1000);
  const page = Math.max(Number(query.page) || 1, 1);
  return { total: list.length, page, limit, items: list.slice((page - 1) * limit, page * limit) };
}

function filterItems(key, items, query) {
  if (key === 'categories' && query.income !== undefined) return items.filter((c) => String(c.income) === query.income);
  if (key === 'budgets' && query.month) {
    const month = L.monthValue(query.month);
    return items.filter((b) => L.sameMonth(L.monthValue(b.month), month));
  }
  return items;
}

function resource(name) {
  const key = RESOURCE_KEYS[name];
  return {
    async list(userId, query) {
      const state = await loadState(userId);
      if (key === 'entries') return filterTransactions(state, query);
      return { items: filterItems(key, state[key], query).map((item) => decorate(key, state, item)) };
    },
    async get(userId, id) {
      const state = await loadState(userId);
      const item = L.byId(state[key], id);
      if (!item) throw notFound();
      return decorate(key, state, item);
    },
    async create(userId, body) {
      const state = await loadState(userId);
      const id = body.id ? String(body.id) : newId();
      if (L.byId(state[key], id)) throw badRequest('Mã bản ghi đã tồn tại, hãy dùng PUT để cập nhật.');
      return decorate(key, state, await upsert(userId, state, key, id, body, { checkBalance: true }));
    },
    async update(userId, id, body) {
      const state = await loadState(userId);
      const created = !L.byId(state[key], id);
      return {
        created,
        item: decorate(key, state, await upsert(userId, state, key, id, body, { checkBalance: true })),
      };
    },
    async remove(userId, id, { cascade }) {
      const state = await loadState(userId);
      await remove(userId, state, key, id, { cascade });
    },
  };
}

module.exports = { RESOURCES: Object.keys(RESOURCE_KEYS), isEntity, loadState, upsert, remove, resource };
