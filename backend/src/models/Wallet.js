const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

const walletSchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 60 },
  savings: { type: Boolean, default: false },
  currency: { type: String, required: true, default: 'VND' },
  opening: { type: Number, required: true, default: 0, min: 0 },
  target: { type: Number, default: 0, min: 0 },
  startDate: { type: Date, default: null },
  deadline: { type: Date, default: null },
  excluded: { type: Boolean, default: false },
  notify: { type: Boolean, default: false },
  symbol: { type: Number, default: null, min: 0 },
  bankBin: { type: String, default: null },
  bankAccount: { type: String, default: null },
  bankHolder: { type: String, default: null },
});
walletSchema.plugin(ownedPlugin);
module.exports = model('Wallet', walletSchema);
