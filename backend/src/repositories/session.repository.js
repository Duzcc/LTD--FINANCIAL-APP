const { RefreshToken } = require('../models');

const findByTokenHash = (tokenHash) => RefreshToken.findOne({ tokenHash });
const existsForDevice = (user, sid) => RefreshToken.exists({ user, sid });
const replaceForUser = async (user, data) => {
  try {
    return await RefreshToken.findOneAndUpdate({ user }, { $set: data }, { upsert: true, new: true });
  } catch (error) {
    if (error.code !== 11000) throw error;
    return RefreshToken.findOneAndUpdate({ user }, { $set: data }, { new: true });
  }
};
const rotate = (id, tokenHash, data) =>
  RefreshToken.findOneAndUpdate({ _id: id, tokenHash }, { $set: data }, { new: true });
const deleteById = async (id) => (await RefreshToken.deleteOne({ _id: id })).deletedCount > 0;
const deleteByTokenHash = (tokenHash, user) => RefreshToken.deleteOne({ tokenHash, ...(user ? { user } : {}) });
const deleteForDevice = (user, sid) => RefreshToken.deleteMany({ user, sid });
const deleteForUser = (user) => RefreshToken.deleteMany({ user });

async function ensureSingleSessionPerUser() {
  const collections = await RefreshToken.db.db
    .listCollections({ name: RefreshToken.collection.collectionName }, { nameOnly: true })
    .toArray();
  if (!collections.length) await RefreshToken.createCollection();

  const duplicates = await RefreshToken.aggregate([
    { $sort: { createdAt: -1, _id: -1 } },
    { $group: { _id: '$user', ids: { $push: '$_id' }, count: { $sum: 1 } } },
    { $match: { count: { $gt: 1 } } },
  ]);
  for (const { ids } of duplicates) {
    await RefreshToken.deleteMany({ _id: { $in: ids.slice(1) } });
  }

  const indexes = await RefreshToken.collection.indexes();
  const oldUserIndex = indexes.find((index) => Object.keys(index.key).join() === 'user' && index.key.user === 1);
  if (oldUserIndex && oldUserIndex.name !== 'one_session_per_user') {
    await RefreshToken.collection.dropIndex(oldUserIndex.name);
  }
  await RefreshToken.collection.createIndex({ user: 1 }, { unique: true, name: 'one_session_per_user' });
  await RefreshToken.collection.createIndex({ tokenHash: 1 }, { unique: true, name: 'tokenHash_1' });
  await RefreshToken.collection.createIndex({ sid: 1 }, { name: 'sid_1' });
}

module.exports = {
  findByTokenHash,
  existsForDevice,
  replaceForUser,
  rotate,
  deleteById,
  deleteByTokenHash,
  deleteForDevice,
  deleteForUser,
  ensureSingleSessionPerUser,
};
