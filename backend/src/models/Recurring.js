const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');
const { KINDS } = require('../services/constants');

// Giao dịch định kỳ (mở rộng): app tự sinh giao dịch khi đến hạn.
const recurringSchema = new Schema({
  kind: { type: String, required: true, enum: Object.keys(KINDS) },
  amount: { type: Number, required: true, min: 0 },
  walletId: { type: String, required: true },
  destinationId: { type: String, default: null },
  categoryId: { type: String, default: null },
  personId: { type: String, default: null },
  note: { type: String, default: '', maxlength: 500 },
  frequency: { type: String, enum: ['daily', 'weekly', 'monthly', 'yearly'], default: 'monthly' },
  interval: { type: Number, default: 1, min: 1, max: 365 },
  startDate: { type: Date, required: true },
  endDate: { type: Date, default: null },
  nextDate: { type: Date, default: null },
  active: { type: Boolean, default: true },
});
recurringSchema.plugin(ownedPlugin);
module.exports = model('Recurring', recurringSchema);
