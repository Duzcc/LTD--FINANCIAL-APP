const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');
const { KINDS } = require('../domain/constants');

const transactionSchema = new Schema({
  kind: { type: String, required: true, enum: Object.keys(KINDS) },
  amount: { type: Number, required: true, min: 0 },
  date: { type: Date, required: true },
  dueDate: { type: Date, default: null },
  note: { type: String, default: '', maxlength: 500 },
  walletId: { type: String, required: true },
  destinationId: { type: String, default: null },
  categoryId: { type: String, default: null },
  personId: { type: String, default: null },
  excluded: { type: Boolean, default: false },
  recurringId: { type: String, default: null },
});
transactionSchema.plugin(ownedPlugin);
transactionSchema.index({ user: 1, date: -1 });
module.exports = model('Transaction', transactionSchema);
