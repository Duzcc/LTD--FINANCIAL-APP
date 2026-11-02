const { Schema, model } = require('mongoose');

// Biến động số dư nhận từ SePay. SePay có thể gửi lại cùng một giao dịch nhiều lần,
// nên (user, providerId) là duy nhất để xử lý đúng một lần.
const bankEventSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true },
  provider: { type: String, default: 'sepay' },
  providerId: { type: String, required: true },
  accountNumber: { type: String, default: '' },
  transferType: { type: String, default: 'in' },
  amount: { type: Number, default: 0 },
  content: { type: String, default: '' },
  occurredAt: { type: Date, default: null },
  result: { type: String, enum: ['matched', 'unmatched', 'ignored'], default: 'unmatched' },
  requestId: { type: Schema.Types.ObjectId, ref: 'PaymentRequest', default: null },
}, { timestamps: true });
bankEventSchema.index({ user: 1, provider: 1, providerId: 1 }, { unique: true });
module.exports = model('BankEvent', bankEventSchema);
