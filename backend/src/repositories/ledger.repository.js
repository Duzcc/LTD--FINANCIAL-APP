const { Wallet, Category, Person, Transaction, Budget, Recurring } = require('../models');

const MODELS = { wallets: Wallet, categories: Category, people: Person, entries: Transaction, budgets: Budget, recurring: Recurring };
const KEYS = Object.keys(MODELS);

async function loadState(user) {
  const lists = await Promise.all(KEYS.map((key) => MODELS[key].find({ user }).sort({ createdAt: 1 })));
  return Object.fromEntries(KEYS.map((key, i) => [key, lists[i].map((doc) => doc.toJSON())]));
}

async function upsert(user, key, id, fields) {
  const doc = await MODELS[key].findOneAndUpdate(
    { user, clientId: id },
    { $set: fields, $setOnInsert: { user, clientId: id } },
    { upsert: true, new: true, runValidators: true },
  );
  return doc.toJSON();
}

const oldestBankWallet = (user) => Wallet.findOne({ user, bankAccount: { $ne: null } }).sort({ createdAt: 1 });

const remove = (user, key, id) => MODELS[key].deleteOne({ user, clientId: id });

const removeWalletDependents = (user, walletId) => Promise.all([
  Transaction.deleteMany({ user, $or: [{ walletId }, { destinationId: walletId }] }),
  Budget.deleteMany({ user, walletId }),
  Recurring.deleteMany({ user, $or: [{ walletId }, { destinationId: walletId }] }),
]);

const seed = (user, { wallets, categories, people }) => Promise.all([
  Wallet.insertMany(wallets.map((w) => ({ ...w, user }))),
  Category.insertMany(categories.map((c) => ({ ...c, user }))),
  Person.insertMany(people.map((p) => ({ ...p, user }))),
]);

module.exports = { KEYS, loadState, upsert, remove, removeWalletDependents, seed, oldestBankWallet };
