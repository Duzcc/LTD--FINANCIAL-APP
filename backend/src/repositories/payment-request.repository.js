const { isValidObjectId } = require('mongoose');
const { PaymentRequest } = require('../models');
const { nullIfDuplicate } = require('./duplicate');

const createUnique = (data) => PaymentRequest.create(data).catch(nullIfDuplicate);
const findById = (id) => PaymentRequest.findById(id);
const findForUser = (id, user) => (isValidObjectId(id) ? PaymentRequest.findOne({ _id: id, user }) : null);
const listForUser = (user, { walletId } = {}) => PaymentRequest
  .find({ user, ...(walletId ? { walletId } : {}) })
  .sort({ createdAt: -1 })
  .limit(50);
const findPendingByCodes = (codes, user) => PaymentRequest.findOne({ code: { $in: codes }, status: 'pending', ...(user ? { user } : {}) });
const findOldestActive = () => PaymentRequest.findOne({ status: 'pending', expiresAt: { $gt: new Date() } }).sort({ createdAt: 1 });
const addPayment = (id, { amount, paidAt, entryId }) => PaymentRequest.findOneAndUpdate(
  { _id: id },
  { $inc: { paidAmount: amount }, $set: { paidAt, entryId } },
  { new: true },
);
const markPaid = (id) => PaymentRequest.updateOne({ _id: id, status: 'pending' }, { $set: { status: 'paid' } });
const save = (request) => request.save();

module.exports = { createUnique, findById, findForUser, listForUser, findPendingByCodes, findOldestActive, addPayment, markPaid, save };
