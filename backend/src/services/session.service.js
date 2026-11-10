const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const config = require('../config');
const users = require('../repositories/user.repository');
const sessions = require('../repositories/session.repository');
const { sha256, randomToken } = require('../utils/crypto');
const { unauthorized } = require('../utils/errors');

const EXPIRED = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.';

const signAccessToken = (user, sid) => jwt.sign(
  { sub: String(user._id), v: user.tokenVersion, ...(sid ? { sid } : {}) },
  config.jwtSecret,
  { expiresIn: config.jwtExpiresIn },
);

function verifyAccessToken(token) {
  try {
    return jwt.verify(token, config.jwtSecret);
  } catch {
    throw unauthorized();
  }
}

async function authenticate(token) {
  const payload = verifyAccessToken(token);
  const [user, live] = await Promise.all([
    users.findById(payload.sub),
    payload.sid ? sessions.existsForDevice(payload.sub, payload.sid) : true,
  ]);
  if (!user || user.tokenVersion !== payload.v || !live) throw unauthorized();
  return { user, sessionId: payload.sid || null };
}

async function issue(user, sid = crypto.randomUUID()) {
  const refreshToken = randomToken(48);
  await sessions.create({
    user: user._id,
    tokenHash: sha256(refreshToken),
    version: user.tokenVersion,
    sid,
    expiresAt: new Date(Date.now() + config.refreshDays * 86400000),
  });
  return { token: signAccessToken(user, sid), refreshToken, user: user.toJSON() };
}

async function rotate(rawRefreshToken) {
  const raw = String(rawRefreshToken || '');
  const current = raw ? await sessions.findByTokenHash(sha256(raw)) : null;
  if (!current || current.expiresAt < new Date()) throw unauthorized(EXPIRED);
  const user = await users.findById(current.user);
  if (!user || user.tokenVersion !== current.version) {
    await sessions.deleteById(current._id);
    throw unauthorized('Phiên đăng nhập đã bị thu hồi.');
  }
  // Mỗi mã làm mới chỉ dùng được một lần. Hai yêu cầu dùng cùng mã một lúc thì chỉ yêu cầu nào
  // xóa được mã cũ mới nhận phiên mới; yêu cầu còn lại bị từ chối.
  const next = await issue(user, current.sid || undefined);
  if (!(await sessions.deleteById(current._id))) {
    await sessions.deleteByTokenHash(sha256(next.refreshToken));
    throw unauthorized(EXPIRED);
  }
  return next;
}

async function revokeAll(user) {
  user.tokenVersion += 1;
  await sessions.deleteForUser(user._id);
}

async function signOut(user, { sessionId, everywhere, refreshToken }) {
  if (everywhere) {
    await revokeAll(user);
    await users.save(user);
  } else if (sessionId) {
    await sessions.deleteForDevice(user._id, sessionId);
  } else if (refreshToken) {
    await sessions.deleteByTokenHash(sha256(String(refreshToken)), user._id);
  }
}

module.exports = { signAccessToken, authenticate, issue, rotate, revokeAll, signOut };
