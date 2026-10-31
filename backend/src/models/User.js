const { Schema, model } = require('mongoose');

// Thực thể NguoiDung (MaNguoiDung, HoTen, Email, MatKhau)
const userSchema = new Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 }, // HoTen
    email: { type: String, required: true, unique: true, lowercase: true, trim: true }, // Email
    passwordHash: { type: String, required: true }, // MatKhau (đã hash bằng bcrypt)
    tokenVersion: { type: Number, default: 0 }, // tăng khi đổi mật khẩu/đăng xuất → thu hồi JWT cũ
    currency: { type: String, default: 'VND' }, // tiền tệ báo cáo
    hideBalance: { type: Boolean, default: false },
    resetCodeHash: { type: String, default: null },
    resetCodeExpires: { type: Date, default: null },
    resetAttempts: { type: Number, default: 0 },
    emailVerified: { type: Boolean, default: false },
    verifyCodeHash: { type: String, default: null },
    verifyCodeExpires: { type: Date, default: null },
    rates: { type: Map, of: Number, default: undefined }, // tỷ giá quy đổi (VND cho 1 đơn vị)
  },
  { timestamps: true }
);
userSchema.set('toJSON', {
  versionKey: false,
  transform: (_d, r) => ({
    id: String(r._id),
    name: r.name,
    email: r.email,
    currency: r.currency,
    hideBalance: r.hideBalance,
    emailVerified: r.emailVerified === true,
    rates: r.rates instanceof Map ? Object.fromEntries(r.rates) : r.rates || undefined,
  }),
});
module.exports = model('User', userSchema);
