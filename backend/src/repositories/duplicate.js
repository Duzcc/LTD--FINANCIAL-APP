// 11000 là mã lỗi trùng khóa của MongoDB
const DUPLICATE_KEY = 11000;

const nullIfDuplicate = (e) => {
  if (e.code === DUPLICATE_KEY) return null;
  throw e;
};

module.exports = { DUPLICATE_KEY, nullIfDuplicate };
