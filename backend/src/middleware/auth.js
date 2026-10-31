const jwt = require('jsonwebtoken');
const config = require('../config');
const { User } = require('../models');
const { unauthorized } = require('../services/errors');

const signToken = (user) =>
  jwt.sign({ sub: String(user._id), v: user.tokenVersion }, config.jwtSecret, { expiresIn: config.jwtExpiresIn });

// Bảo vệ API: chỉ cho phép truy cập khi có JWT hợp lệ; req.user là người dùng hiện tại.
async function requireAuth(req, _res, next) {
  try {
    const header = req.headers.authorization || '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) throw unauthorized('Bạn cần đăng nhập để tiếp tục.');
    let payload;
    try { payload = jwt.verify(token, config.jwtSecret); } catch { throw unauthorized(); }
    const user = await User.findById(payload.sub);
    if (!user || user.tokenVersion !== payload.v) throw unauthorized();
    req.user = user;
    next();
  } catch (e) { next(e); }
}
module.exports = { requireAuth, signToken };
