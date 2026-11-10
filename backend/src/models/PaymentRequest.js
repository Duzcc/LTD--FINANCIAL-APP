const { Schema, model } = require('mongoose');

const paymentRequestSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  code: { type: String, required: true, unique: true },
  walletId: { type: String, required: true },
  kind: { type: String, enum: ['income', 'collect'], default: 'income' },
  amount: { type: Number, default: null, min: 0 },
  categoryId: { type: String, default: null },
  personId: { type: String, default: null },
  note: { type: String, default: '', maxlength: 100 },
  status: { type: String, enum: ['pending', 'paid', 'cancelled'], default: 'pending' },
  paidAmount: { type: Number, default: 0 },
  paidAt: { type: Date, default: null },
  entryId: { type: String, default: null },
  expiresAt: { type: Date, required: true },
}, { timestamps: true });
paymentRequestSchema.index({ status: 1, expiresAt: 1, createdAt: 1 });
paymentRequestSchema.set('toJSON', {
  versionKey: false,
  transform: (_d, r) => ({
    id: String(r._id),
    code: r.code,
    walletId: r.walletId,
    kind: r.kind,
    amount: r.amount,
    categoryId: r.categoryId,
    personId: r.personId,
    note: r.note,
    status: r.status !== 'pending' || r.expiresAt > new Date() ? r.status : 'expired',
    paidAmount: r.paidAmount,
    paidAt: r.paidAt,
    entryId: r.entryId,
    expiresAt: r.expiresAt,
    createdAt: r.createdAt,
  }),
});
module.exports = model('PaymentRequest', paymentRequestSchema);
