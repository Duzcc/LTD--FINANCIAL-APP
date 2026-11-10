const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

const categorySchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 60 },
  income: { type: Boolean, required: true },
  symbol: { type: Number, default: 0 },
  isDefault: { type: Boolean, default: false },
});
categorySchema.plugin(ownedPlugin);
module.exports = model('Category', categorySchema);
