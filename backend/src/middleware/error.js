const { ApiError } = require('../services/errors');
const config = require('../config');

function notFoundRoute(req, res) {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: `Không có API ${req.method} ${req.originalUrl}` } });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, _next) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ error: { code: err.code, message: err.message } });
  }
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_JSON', message: 'Dữ liệu gửi lên không đúng định dạng JSON.' } });
  }
  if (err.name === 'ValidationError' || err.name === 'CastError') {
    return res.status(400).json({ error: { code: 'VALIDATION_ERROR', message: 'Dữ liệu không hợp lệ.' } });
  }
  if (err.code === 11000) {
    return res.status(409).json({ error: { code: 'DUPLICATE', message: 'Dữ liệu đã tồn tại.' } });
  }
  if (!config.isProduction || process.env.LOG_ERRORS) console.error(err);
  return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Máy chủ gặp lỗi, vui lòng thử lại sau.' } });
}
module.exports = { notFoundRoute, errorHandler };
