const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');
const { KINDS } = require('../services/constants');

// Thực thể GiaoDich (MaGiaoDich, LoaiGiaoDich, SoTien, NgayGiaoDich, NgayDenHan, GhiChu, MaVi, MaDanhMuc, MaDoiTuong)
const transactionSchema = new Schema({
  kind: { type: String, required: true, enum: Object.keys(KINDS) }, // LoaiGiaoDich
  amount: { type: Number, required: true, min: 0 }, // SoTien
  date: { type: Date, required: true }, // NgayGiaoDich
  dueDate: { type: Date, default: null }, // NgayDenHan (vay/nợ)
  note: { type: String, default: '', maxlength: 500 }, // GhiChu
  walletId: { type: String, required: true }, // MaVi
  destinationId: { type: String, default: null }, // ví nhận (chuyển tiền)
  categoryId: { type: String, default: null }, // MaDanhMuc
  personId: { type: String, default: null }, // MaDoiTuong
  excluded: { type: Boolean, default: false }, // không tính vào báo cáo
  recurringId: { type: String, default: null }, // sinh từ giao dịch định kỳ nào
});
transactionSchema.plugin(ownedPlugin);
transactionSchema.index({ user: 1, date: -1 });
module.exports = model('Transaction', transactionSchema);
