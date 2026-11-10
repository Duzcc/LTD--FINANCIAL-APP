const { Schema, model } = require('mongoose');
const { ownedPlugin } = require('./plugin');

const personSchema = new Schema({
  name: { type: String, required: true, trim: true, maxlength: 80 },
  group: { type: String, default: 'Cá nhân', trim: true, maxlength: 60 },
});
personSchema.plugin(ownedPlugin);
module.exports = model('Person', personSchema);
