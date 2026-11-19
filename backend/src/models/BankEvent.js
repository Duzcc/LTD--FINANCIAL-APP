const { Schema, model } = require('mongoose');

const bankEventSchema = new Schema(
  {
    user: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    provider: { type: String, default: 'sepay' },
    providerId: { type: String, required: true },
    accountNumber: { type: String, default: '' },
    transferType: { type: String, default: 'in' },
    amount: { type: Number, default: 0 },
    content: { type: String, default: '' },
    occurredAt: { type: Date, default: null },
    result: { type: String, enum: ['matched', 'recorded', 'linked', 'unmatched', 'ignored'], default: 'unmatched' },
    requestId: { type: Schema.Types.ObjectId, ref: 'PaymentRequest', default: null },
    entryId: { type: String, default: null },
  },
  { timestamps: true },
);
bankEventSchema.index({ user: 1, provider: 1, providerId: 1 }, { unique: true });
module.exports = model('BankEvent', bankEventSchema);
