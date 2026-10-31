const { Types } = require('mongoose');
const { Wallet, Category, Person, Transaction, Budget, Recurring } = require('../models');
const L = require('./ledger');
const { notFound, conflict, badRequest } = require('./errors');

const plain = (doc) => doc.toJSON();

const ENTITIES = {
  wallets: { Model: Wallet, validate: L.validateWallet },
  categories: { Model: Category, validate: L.validateCategory },
  people: { Model: Person, validate: L.validatePerson },
  entries: { Model: Transaction, validate: L.validateEntry },
  budgets: { Model: Budget, validate: L.validateBudget },
  recurring: { Model: Recurring, validate: L.validateRecurring },
};
// Tên tài nguyên ở URL → khóa trong state
const RESOURCE = { wallets: 'wallets', categories: 'categories', people: 'people', transactions: 'entries', budgets: 'budgets', recurring: 'recurring' };
const KEYS = ['wallets', 'categories', 'people', 'entries', 'budgets', 'recurring'];

async function loadState(user) {
  const lists = await Promise.all(KEYS.map((k) => ENTITIES[k].Model.find({ user }).sort({ createdAt: 1 })));
  return Object.fromEntries(KEYS.map((k, i) => [k, lists[i].map(plain)]));
}

const newId = () => new Types.ObjectId().toHexString();
function checkId(id) {
  if (typeof id !== 'string' || !/^[A-Za-z0-9_\-]{1,64}$/.test(id)) throw badRequest('Mã bản ghi không hợp lệ.');
  return id;
}

/** Tạo mới hoặc thay thế bản ghi (idempotent theo id), cập nhật state trong bộ nhớ. */
async function upsert(user, state, key, id, data) {
  const { Model, validate } = ENTITIES[key];
  const value = validate(state, data || {}, checkId(id));
  const { id: _omit, ...fields } = value;
  const doc = await Model.findOneAndUpdate(
    { user, clientId: id },
    { $set: fields, $setOnInsert: { user, clientId: id } },
    { upsert: true, new: true, runValidators: true }
  );
  const saved = plain(doc);
  const list = state[key];
  const i = list.findIndex((x) => x.id === id);
  if (i < 0) list.push(saved); else list[i] = saved;
  return saved;
}

async function remove(user, state, key, id, { cascade = false, missingOk = false } = {}) {
  const list = state[key];
  const current = L.byId(list, id);
  if (!current) {
    if (missingOk) return { deleted: 0 };
    throw notFound();
  }
  if (key === 'wallets') {
    const refs = L.walletRefs(state, id);
    if (refs.total > 0 && !cascade) {
      throw conflict(`Ví đang có ${refs.entries} giao dịch và ${refs.budgets} ngân sách. Gửi cascade=true để xóa kèm dữ liệu liên quan.`, 'HAS_REFERENCES');
    }
    if (cascade) {
      await Transaction.deleteMany({ user, $or: [{ walletId: id }, { destinationId: id }] });
      await Budget.deleteMany({ user, walletId: id });
      await Recurring.deleteMany({ user, $or: [{ walletId: id }, { destinationId: id }] });
      state.entries = state.entries.filter((e) => e.walletId !== id && e.destinationId !== id);
      state.budgets = state.budgets.filter((b) => b.walletId !== id);
      state.recurring = state.recurring.filter((r) => r.walletId !== id && r.destinationId !== id);
    }
  }
  if (key === 'categories' && L.categoryRefs(state, id) > 0) throw conflict('Danh mục đang được sử dụng.', 'HAS_REFERENCES');
  if (key === 'people' && L.personRefs(state, id) > 0) throw conflict('Đối tượng đang có giao dịch.', 'HAS_REFERENCES');
  await ENTITIES[key].Model.deleteOne({ user, clientId: id });
  state[key] = state[key].filter((x) => x.id !== id);
  return { deleted: 1 };
}

module.exports = { ENTITIES, RESOURCE, KEYS, loadState, upsert, remove, newId };
