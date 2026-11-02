const { Schema, model } = require('mongoose');

// Thực thể NguoiDung (MaNguoiDung, HoTen, Email, MatKhau)
const userSchema = new Schema(
  {
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 50 }, // HoTen
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 }, // Email
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
    failedLogins: { type: Number, default: 0 }, // số lần nhập sai mật khẩu liên tiếp
    lockUntil: { type: Date, default: null }, // tạm khóa đăng nhập đến thời điểm này
    sepayKeyHash: { type: String, default: null }, // API key webhook SePay (băm SHA-256)
    sepayKeyHint: { type: String, default: null }, // 4 ký tự cuối để nhận biết khóa
    rates: { type: Map, of: Number, default: undefined }, // tỷ giá quy đổi (VND cho 1 đơn vị)
  },
  { timestamps: true }
);
// Chỉ những tài khoản đã tạo khóa mới tham gia chỉ mục duy nhất (bỏ qua giá trị null).
userSchema.index({ sepayKeyHash: 1 }, { unique: true, partialFilterExpression: { sepayKeyHash: { $type: 'string' } } });
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
