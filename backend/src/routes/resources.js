const express = require('express');
const wrap = require('../middleware/async');
const { RESOURCE, loadState, upsert, remove, newId } = require('../services/store');
const L = require('../services/ledger');
const { isDebt, isIncome, isExpense } = require('../services/constants');
const { notFound, badRequest } = require('../services/errors');

function decorate(key, state, item) {
  if (key === 'wallets') return { ...item, balance: L.balance(state, item.id) };
  if (key === 'budgets') return { ...item, used: L.used(state, item) };
  return item;
}

function filterTransactions(state, q) {
  const from = L.date(q.from, 'from');
  const to = L.date(q.to, 'to');
  const text = String(q.q || '').trim().toLowerCase();
  const type = q.type || 'all';
  const cat = (id) => L.byId(state.categories, id)?.name || '';
  const person = (id) => L.byId(state.people, id)?.name || '';
  let list = state.entries.filter((e) => {
    const d = new Date(e.date);
    if (from && d < from) return false;
    if (to && d > to) return false;
    if (q.walletId && e.walletId !== q.walletId && e.destinationId !== q.walletId) return false;
    if (q.categoryId && e.categoryId !== q.categoryId) return false;
    if (q.personId && e.personId !== q.personId) return false;
    if (type === 'debt' && !isDebt(e.kind)) return false;
    if (type === 'income' && !isIncome(e.kind)) return false;
    if (type === 'expense' && !isExpense(e.kind)) return false;
    if (!['all', 'debt', 'income', 'expense'].includes(type) && e.kind !== type) return false;
    if (text && !`${cat(e.categoryId)} ${e.note} ${person(e.personId)} ${e.amount}`.toLowerCase().includes(text)) return false;
    return true;
  });
  const dir = q.order === 'asc' ? 1 : -1;
  list = list.sort((a, b) => dir * (q.sort === 'amount' ? a.amount - b.amount : new Date(a.date) - new Date(b.date)));
  const limit = Math.min(Math.max(Number(q.limit) || 500, 1), 1000);
  const page = Math.max(Number(q.page) || 1, 1);
  return { total: list.length, page, limit, items: list.slice((page - 1) * limit, page * limit) };
}

function resourceRouter(resource) {
  const key = RESOURCE[resource];
  const router = express.Router();

  router.get('/', wrap(async (req, res) => {
    const state = await loadState(req.user._id);
    if (key === 'entries') {
      const result = filterTransactions(state, req.query);
      return res.json(result);
    }
    let items = state[key];
    if (key === 'categories' && req.query.income !== undefined) items = items.filter((c) => String(c.income) === req.query.income);
    if (key === 'budgets' && req.query.month) {
      const m = L.monthValue(req.query.month);
      items = items.filter((b) => L.sameMonth(L.monthValue(b.month), m));
    }
    res.json({ items: items.map((i) => decorate(key, state, i)) });
  }));

  router.get('/:id', wrap(async (req, res) => {
    const state = await loadState(req.user._id);
    const item = L.byId(state[key], req.params.id);
    if (!item) throw notFound();
    res.json(decorate(key, state, item));
  }));

  router.post('/', wrap(async (req, res) => {
    const state = await loadState(req.user._id);
    const id = req.body.id ? String(req.body.id) : newId();
    if (L.byId(state[key], id)) throw badRequest('Mã bản ghi đã tồn tại, hãy dùng PUT để cập nhật.');
    const saved = await upsert(req.user._id, state, key, id, req.body);
    res.status(201).json(decorate(key, state, saved));
  }));

  router.put('/:id', wrap(async (req, res) => {
    const state = await loadState(req.user._id);
    const existed = !!L.byId(state[key], req.params.id);
    const saved = await upsert(req.user._id, state, key, req.params.id, req.body);
    res.status(existed ? 200 : 201).json(decorate(key, state, saved));
  }));

  router.delete('/:id', wrap(async (req, res) => {
    const state = await loadState(req.user._id);
    await remove(req.user._id, state, key, req.params.id, { cascade: req.query.cascade === 'true' });
    res.status(204).end();
  }));
  return router;
}
module.exports = { resourceRouter, filterTransactions };
