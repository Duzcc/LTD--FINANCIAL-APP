const asyncHandler = require('./async-handler');
const sessionService = require('../services/session.service');
const { unauthorized } = require('../utils/errors');

const requireAuth = asyncHandler(async (req, _res, next) => {
  const [scheme, token] = String(req.headers.authorization || '').split(' ');
  if (scheme !== 'Bearer' || !token) throw unauthorized('Bạn cần đăng nhập để tiếp tục.');
  const { user, sessionId } = await sessionService.authenticate(token);
  req.user = user;
  req.sessionId = sessionId;
  next();
});

module.exports = { requireAuth };
