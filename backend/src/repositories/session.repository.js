const { RefreshToken } = require('../models');

const create = (data) => RefreshToken.create(data);
const findByTokenHash = (tokenHash) => RefreshToken.findOne({ tokenHash });
const existsForDevice = (user, sid) => RefreshToken.exists({ user, sid });
const deleteById = async (id) => (await RefreshToken.deleteOne({ _id: id })).deletedCount > 0;
const deleteByTokenHash = (tokenHash, user) => RefreshToken.deleteOne({ tokenHash, ...(user ? { user } : {}) });
const deleteForDevice = (user, sid) => RefreshToken.deleteMany({ user, sid });
const deleteForUser = (user) => RefreshToken.deleteMany({ user });

module.exports = { create, findByTokenHash, existsForDevice, deleteById, deleteByTokenHash, deleteForDevice, deleteForUser };
