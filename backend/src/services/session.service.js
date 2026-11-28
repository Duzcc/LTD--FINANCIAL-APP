const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const config = require('../config');
const users = require('../repositories/user.repository');
const sessions = require('../repositories/session.repository');
const { sha256, randomToken } = require('../utils/crypto');
const { unauthorized } = require('../utils/errors');

const EXPIRED = 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.';

const signAccessToken = (user, sid) =>
  jwt.sign({ sub: String(user._id), v: user.tokenVersion, ...(sid ? { sid } : {}) }, config.jwtSecret, {
    algorithm: 'HS256',
    expiresIn: config.jwtExpiresIn,
  });

function verifyAccessToken(token) {
  try {
    return jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
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
  const stored = await sessions.replaceForUser(user._id, {
    tokenHash: sha256(refreshToken),
    version: user.tokenVersion,
    sid,
    expiresAt: new Date(Date.now() + config.refreshDays * 86400000),
  });
  if (!stored) throw unauthorized();
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
  const refreshToken = randomToken(48);
  const rotated = await sessions.rotate(current._id, current.tokenHash, {
    tokenHash: sha256(refreshToken),
    version: user.tokenVersion,
    expiresAt: new Date(Date.now() + config.refreshDays * 86400000),
  });
  if (!rotated) throw unauthorized(EXPIRED);
  return { token: signAccessToken(user, current.sid), refreshToken, user: user.toJSON() };
}

async function revokeAll(user, { incrementVersion = true } = {}) {
  if (incrementVersion) user.tokenVersion += 1;
  await sessions.deleteForUser(user._id);
}

async function signOut(user, { sessionId, refreshToken }) {
  if (sessionId) {
    await sessions.deleteForDevice(user._id, sessionId);
  } else if (refreshToken) {
    await sessions.deleteByTokenHash(sha256(String(refreshToken)), user._id);
  }
}

module.exports = { signAccessToken, authenticate, issue, rotate, revokeAll, signOut };
