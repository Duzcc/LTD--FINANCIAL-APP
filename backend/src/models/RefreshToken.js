const { Schema, model } = require('mongoose');

const refreshSchema = new Schema(
  {
    user: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    tokenHash: { type: String, required: true, unique: true },
    version: { type: Number, required: true },
    sid: { type: String, index: true },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true, autoIndex: false },
);
refreshSchema.index({ user: 1 }, { unique: true, name: 'one_session_per_user' });
module.exports = model('RefreshToken', refreshSchema);
