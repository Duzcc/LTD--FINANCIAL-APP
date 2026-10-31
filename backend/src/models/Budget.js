const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

// Thực thể NganSach (MaNganSach, SoTien, NgayBatDau, NgayKetThuc, MaVi, MaDanhMuc)
// categoryId = null: mục tiêu tổng của cả tháng.
const budgetSchema = new Schema({
  amount: { type: Number, required: true, min: 0 }, // SoTien
  month: { type: Date, required: true }, // ngày đầu tháng
  startDate: { type: Date, required: true }, // NgayBatDau
  endDate: { type: Date, required: true }, // NgayKetThuc
  categoryId: { type: String, default: null }, // MaDanhMuc
  walletId: { type: String, default: null }, // MaVi (null = mọi ví cùng tiền tệ)
  currency: { type: String, default: 'VND' },
  income: { type: Boolean, default: false }, // mục tiêu thu (true) hay ngân sách chi (false)
});
budgetSchema.plugin(ownedPlugin);
// Trả tháng dạng "YYYY-MM-01" để client không bị lệch múi giờ.
const baseTransform = budgetSchema.get('toJSON').transform;
budgetSchema.set('toJSON', {
  versionKey: false,
  transform: (doc, ret) => {
    const out = baseTransform(doc, ret);
    const m = new Date(out.month);
    out.month = `${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}-01`;
    delete out.startDate;
    delete out.endDate;
    return out;
  },
}); 
module.exports = model('Budget', budgetSchema);
