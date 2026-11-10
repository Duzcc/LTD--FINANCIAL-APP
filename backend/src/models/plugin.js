const { Schema, Types } = require('mongoose');

function ownedPlugin(schema) {
  schema.add({
    user: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    clientId: { type: String, required: true, default: () => new Types.ObjectId().toHexString() },
  });
  schema.index({ user: 1, clientId: 1 }, { unique: true });
  schema.set('timestamps', true);
  schema.set('toJSON', {
    versionKey: false,
    transform: (_doc, ret) => {
      ret.id = ret.clientId;
      delete ret._id;
      delete ret.clientId;
      delete ret.user;
      delete ret.createdAt;
      delete ret.updatedAt;
      return ret;
    },
  });
}
module.exports = { ownedPlugin };
