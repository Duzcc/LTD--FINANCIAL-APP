const { Schema, model } = require('mongoose');

const userSchema = new Schema(
  {
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 50 },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 },
    passwordHash: { type: String, required: true },
    tokenVersion: { type: Number, default: 0 },
    currency: { type: String, default: 'VND' },
    hideBalance: { type: Boolean, default: false },
    resetCodeHash: { type: String, default: null },
    resetCodeExpires: { type: Date, default: null },
    resetAttempts: { type: Number, default: 0 },
    emailVerified: { type: Boolean, default: false },
    verifyCodeHash: { type: String, default: null },
    verifyCodeExpires: { type: Date, default: null },
    failedLogins: { type: Number, default: 0 },
    lockUntil: { type: Date, default: null },
    sepayKeyHash: { type: String, default: null },
    sepayKeyHint: { type: String, default: null },
    rates: { type: Map, of: Number, default: undefined },
  },
  { timestamps: true },
);
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
