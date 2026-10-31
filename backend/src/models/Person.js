const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

// Thực thể DoiTuong (MaDoiTuong, TenDoiTuong)
const personSchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 80 }, // TenDoiTuong
  group: { type: String, default: 'Cá nhân', trim: true, maxlength: 60 },
});
personSchema.plugin(ownedPlugin);
module.exports = model('Person', personSchema);
