const { Schema, model } = require('mongoose');

const refreshSchema = new Schema({
  user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  tokenHash: { type: String, required: true, unique: true },
  version: { type: Number, required: true },
  sid: { type: String, index: true },
  expiresAt: { type: Date, required: true },
}, { timestamps: true });
module.exports = model('RefreshToken', refreshSchema);
