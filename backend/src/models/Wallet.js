const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

// Thực thể Vi (MaVi, TenVi, LoaiVi, DonViTien, SoDuHienTai, SoTienMucTieu, NgayBatDau, NgayKetThuc)
// SoDuHienTai không lưu cứng mà được tính = số dư ban đầu + các giao dịch (trả về ở trường "balance").
const walletSchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 60 }, // TenVi
  savings: { type: Boolean, default: false }, // LoaiVi: false = CoBan, true = TietKiem
  currency: { type: String, required: true, default: 'VND' }, // DonViTien
  opening: { type: Number, required: true, default: 0, min: 0 }, // số dư ban đầu
  target: { type: Number, default: 0, min: 0 }, // SoTienMucTieu
  startDate: { type: Date, default: null }, // NgayBatDau
  deadline: { type: Date, default: null }, // NgayKetThuc
  excluded: { type: Boolean, default: false }, // Không tính vào tổng
});
walletSchema.plugin(ownedPlugin);
module.exports = model('Wallet', walletSchema);
