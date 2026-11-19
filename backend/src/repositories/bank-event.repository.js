const { BankEvent } = require('../models');
const { nullIfDuplicate } = require('./duplicate');

const createUnique = (data) => BankEvent.create(data).catch(nullIfDuplicate);
const deleteById = (id) => BankEvent.deleteOne({ _id: id });
const save = (event) => event.save();
const linkedEntryIds = async (user) =>
  (await BankEvent.find({ user, entryId: { $ne: null } }, { entryId: 1 }).lean()).map((e) => e.entryId);

module.exports = { createUnique, deleteById, save, linkedEntryIds };
