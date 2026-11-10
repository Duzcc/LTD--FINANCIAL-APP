const rateLimit = require('express-rate-limit');
const config = require('../config');

const limiter = (limit, windowMs, message, extra = {}) => rateLimit({
  windowMs,
  limit,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: { code: 'TOO_MANY_REQUESTS', message } },
  ...extra,
});

const authLimiter = limiter(config.rateLimits.auth, 15 * 60 * 1000, 'Bạn thử quá nhiều lần, vui lòng đợi ít phút.');
const aiLimiter = limiter(config.rateLimits.ai, 60 * 1000, 'Bạn thao tác quá nhanh, vui lòng đợi một chút.', {
  keyGenerator: (req) => String(req.user?._id || req.ip),
});
const webhookLimiter = limiter(config.rateLimits.webhook, 60 * 1000, 'Quá nhiều yêu cầu webhook.');

module.exports = { authLimiter, aiLimiter, webhookLimiter };
