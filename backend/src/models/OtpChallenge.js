const { Schema, model } = require('mongoose');

const otpSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  purpose: { type: String, enum: ['login', 'register'], required: true },
  tokenHash: { type: String, required: true, unique: true },
  codeHash: { type: String, required: true },
  expiresAt: { type: Date, required: true },
  attempts: { type: Number, default: 0 },
  sends: { type: Number, default: 1 },
  lastSentAt: { type: Date, default: Date.now },
  pendingName: { type: String, default: null },
  pendingPasswordHash: { type: String, default: null },
  purgeAt: { type: Date, required: true },
}, { timestamps: true });
otpSchema.index({ purgeAt: 1 }, { expireAfterSeconds: 0 });
module.exports = model('OtpChallenge', otpSchema);
