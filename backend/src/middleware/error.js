const config = require('../config');
const { ApiError } = require('../utils/errors');
const { DUPLICATE_KEY } = require('../repositories/duplicate');

const errorBody = (code, message) => ({ error: { code, message } });

function notFoundRoute(req, res) {
  res.status(404).json(errorBody('NOT_FOUND', `Không có API ${req.method} ${req.originalUrl}`));
}

function errorHandler(err, req, res, _next) {
  if (err instanceof ApiError) return res.status(err.status).json(errorBody(err.code, err.message));
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json(errorBody('BAD_JSON', 'Dữ liệu gửi lên không đúng định dạng JSON.'));
  }
  if (err.name === 'ValidationError' || err.name === 'CastError') {
    return res.status(400).json(errorBody('VALIDATION_ERROR', 'Dữ liệu không hợp lệ.'));
  }
  if (err.code === DUPLICATE_KEY) return res.status(409).json(errorBody('DUPLICATE', 'Dữ liệu đã tồn tại.'));
  if (!config.isProduction || process.env.LOG_ERRORS) console.error(err);
  return res.status(500).json(errorBody('SERVER_ERROR', 'Máy chủ gặp lỗi, vui lòng thử lại sau.'));
}

module.exports = { notFoundRoute, errorHandler };
