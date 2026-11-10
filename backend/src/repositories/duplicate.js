// MongoDB báo lỗi 11000 khi thêm bản ghi trùng giá trị phải là duy nhất (ví dụ cùng mã giao dịch).
const DUPLICATE_KEY = 11000;

const nullIfDuplicate = (e) => {
  if (e.code === DUPLICATE_KEY) return null;
  throw e;
};

module.exports = { DUPLICATE_KEY, nullIfDuplicate };
