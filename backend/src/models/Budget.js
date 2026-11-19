const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

const budgetSchema = new Schema({
  amount: { type: Number, required: true, min: 0 },
  month: { type: Date, required: true },
  startDate: { type: Date, required: true },
  endDate: { type: Date, required: true },
  categoryId: { type: String, default: null },
  walletId: { type: String, default: null },
  currency: { type: String, default: 'VND' },
  income: { type: Boolean, default: false },
});
budgetSchema.plugin(ownedPlugin);
const baseTransform = budgetSchema.get('toJSON').transform;
budgetSchema.set('toJSON', {
  versionKey: false,
  transform: (doc, ret) => {
    const out = baseTransform(doc, ret);
    const m = new Date(out.month);
    out.month = `${m.getFullYear()}-${String(m.getMonth() + 1).padStart(2, '0')}-01`;
    delete out.startDate;
    delete out.endDate;
    return out;
  },
});
module.exports = model('Budget', budgetSchema);
