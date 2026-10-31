const router = require('express').Router();
const wrap = require('../middleware/async');
const { ENTITIES, loadState, upsert, remove } = require('../services/store');
const { badRequest, ApiError } = require('../services/errors');

// Ảnh chụp toàn bộ dữ liệu của người dùng (dùng khi đăng nhập trên thiết bị mới).
router.get('/', wrap(async (req, res) => {
  const state = await loadState(req.user._id);
  res.json({ user: req.user.toJSON(), ...state, serverTime: new Date().toISOString() });
}));

// Áp dụng tuần tự một danh sách thao tác từ hàng đợi đồng bộ của app.
// ops: [{ entity: 'wallets'|'categories'|'people'|'entries'|'budgets', action: 'upsert'|'delete', id, data }]
router.post('/batch', wrap(async (req, res) => {
  const ops = req.body.ops;
  if (!Array.isArray(ops) || ops.length > 2000) throw badRequest('Danh sách thao tác không hợp lệ.');
  const state = await loadState(req.user._id);
  let applied = 0;
  for (const [index, op] of ops.entries()) {
    try {
      if (!ENTITIES[op.entity]) throw badRequest(`Loại dữ liệu không hợp lệ: ${op.entity}`);
      if (op.action === 'upsert') await upsert(req.user._id, state, op.entity, String(op.id), op.data);
      else if (op.action === 'delete') await remove(req.user._id, state, op.entity, String(op.id), { missingOk: true, cascade: op.cascade === true });
      else throw badRequest('Thao tác không hợp lệ.');
      applied += 1;
    } catch (e) {
      if (e instanceof ApiError) {
        return res.status(e.status).json({ applied, failedIndex: index, error: { code: e.code, message: e.message } });
      }
      throw e;
    }
  }
  res.json({ applied });
}));

module.exports = router;
