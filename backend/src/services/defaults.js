// Dữ liệu khởi tạo cho tài khoản mới, trùng với dữ liệu mặc định của app.
const defaultWallets = [{ clientId: 'cash', name: 'Tiền mặt', currency: 'VND' }];
const defaultCategories = [
  ['food', 'Ăn uống', false, 0], ['life', 'Sinh hoạt', false, 1], ['house', 'Nhà cửa', false, 2],
  ['self', 'Bản thân', false, 3], ['transport', 'Đi lại', false, 4], ['health', 'Sức khỏe', false, 5],
  ['child', 'Con cái', false, 6], ['salary', 'Lương', true, 7], ['bonus', 'Thưởng', true, 8],
  ['business', 'Kinh doanh', true, 11], ['other_income', 'Thu nhập khác', true, 12],
].map(([clientId, name, income, symbol]) => ({ clientId, name, income, symbol, isDefault: true }));
const defaultPeople = [{ clientId: 'self', name: 'Bản thân', group: 'Cá nhân' }];

module.exports = { defaultWallets, defaultCategories, defaultPeople };
