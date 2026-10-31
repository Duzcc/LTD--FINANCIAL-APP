const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

// Thực thể DanhMuc (MaDanhMuc, TenDanhMuc, LoaiDanhMuc)
const categorySchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 60 }, // TenDanhMuc
  income: { type: Boolean, required: true }, // danh mục thu (true) hay chi (false)
  symbol: { type: Number, default: 0 }, // biểu tượng
  isDefault: { type: Boolean, default: false }, // LoaiDanhMuc: MacDinh / KhongMacDinh
});
categorySchema.plugin(ownedPlugin);
module.exports = model('Category', categorySchema);
