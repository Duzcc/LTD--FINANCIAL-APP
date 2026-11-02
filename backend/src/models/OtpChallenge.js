const { Schema, model } = require('mongoose');

// Phiên xác thực OTP: sau khi nhập đúng mật khẩu (hoặc đăng ký), một mã 6 số được gửi tới email.
// Ứng dụng giữ otpToken (chuỗi ngẫu nhiên, chỉ lưu bản băm) và gửi kèm mã để nhận phiên đăng nhập.
const otpSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  purpose: { type: String, enum: ['login', 'register'], required: true },
  tokenHash: { type: String, required: true, unique: true },
  codeHash: { type: String, required: true },
  expiresAt: { type: Date, required: true }, // hạn của mã hiện tại
  attempts: { type: Number, default: 0 }, // số lần nhập sai
  sends: { type: Number, default: 1 }, // số lần đã gửi mã
  lastSentAt: { type: Date, default: Date.now },
  purgeAt: { type: Date, required: true }, // MongoDB tự xóa bản ghi sau thời điểm này
}, { timestamps: true });
otpSchema.index({ purgeAt: 1 }, { expireAfterSeconds: 0 });
module.exports = model('OtpChallenge', otpSchema);
