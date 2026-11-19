const {
  User,
  Wallet,
  Category,
  Person,
  Transaction,
  Budget,
  Recurring,
  RefreshToken,
  OtpChallenge,
  PaymentRequest,
  BankEvent,
} = require('../models');

const OWNED_MODELS = [
  Wallet,
  Category,
  Person,
  Transaction,
  Budget,
  Recurring,
  RefreshToken,
  OtpChallenge,
  PaymentRequest,
  BankEvent,
];

const findById = (id) => User.findById(id);
const findByEmail = (email) => User.findOne({ email });
const findBySepayKeyHash = (hash) => User.findOne({ sepayKeyHash: hash });
const create = (data) => User.create(data);
const save = (user) => user.save();

async function deleteWithData(userId) {
  await Promise.all(OWNED_MODELS.map((Model) => Model.deleteMany({ user: userId })));
  await User.deleteOne({ _id: userId });
}

module.exports = { findById, findByEmail, findBySepayKeyHash, create, save, deleteWithData };
