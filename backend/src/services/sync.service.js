const ledger = require('./ledger.service');
const { badRequest, ApiError } = require('../utils/errors');

const MAX_OPS = 2000;

async function snapshot(user) {
  const state = await ledger.loadState(user._id);
  return { user: user.toJSON(), ...state, serverTime: new Date().toISOString() };
}

async function applyOp(userId, state, op) {
  if (!ledger.isEntity(op.entity)) throw badRequest(`Loại dữ liệu không hợp lệ: ${op.entity}`);
  if (op.action === 'upsert') return ledger.upsert(userId, state, op.entity, String(op.id), op.data);
  if (op.action === 'delete') {
    return ledger.remove(userId, state, op.entity, String(op.id), { missingOk: true, cascade: op.cascade === true });
  }
  throw badRequest('Thao tác không hợp lệ.');
}

async function applyBatch(userId, ops) {
  if (!Array.isArray(ops) || ops.length > MAX_OPS) throw badRequest('Danh sách thao tác không hợp lệ.');
  const state = await ledger.loadState(userId);
  // Dừng ở thao tác lỗi đầu tiên và báo cho app biết đã lưu được bao nhiêu thao tác trước đó.
  for (const [index, op] of ops.entries()) {
    try {
      await applyOp(userId, state, op);
    } catch (e) {
      if (!(e instanceof ApiError)) throw e;
      return { status: e.status, body: { applied: index, failedIndex: index, error: { code: e.code, message: e.message } } };
    }
  }
  return { status: 200, body: { applied: ops.length } };
}

module.exports = { snapshot, applyBatch };
