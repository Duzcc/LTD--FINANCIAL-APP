const { Schema, model } = require('mongoose');

// Refresh token dạng chuỗi ngẫu nhiên, chỉ lưu bản băm SHA-256; xoay vòng mỗi lần dùng.
const refreshSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  tokenHash: { type: String, required: true, unique: true },
  version: { type: Number, required: true }, // tokenVersion của người dùng lúc cấp
  sid: { type: String, index: true }, // mã phiên của một thiết bị, giữ nguyên qua các lần xoay vòng
  expiresAt: { type: Date, required: true },
}, { timestamps: true });
module.exports = model('RefreshToken', refreshSchema);
