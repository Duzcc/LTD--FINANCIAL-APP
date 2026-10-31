class ApiError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
const badRequest = (m, code = 'VALIDATION_ERROR') => new ApiError(400, m, code);
const notFound = (m = 'Không tìm thấy dữ liệu.') => new ApiError(404, m, 'NOT_FOUND');
const conflict = (m, code = 'CONFLICT') => new ApiError(409, m, code);
const unauthorized = (m = 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.') => new ApiError(401, m, 'UNAUTHORIZED');
module.exports = { ApiError, badRequest, notFound, conflict, unauthorized };
