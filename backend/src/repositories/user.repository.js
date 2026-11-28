const {
  User,
  Wallet,
  Category,
  Person,
  Transaction,
  Budget,
  Recurring,
  RefreshToken,
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
  PaymentRequest,
  BankEvent,
];

const findById = (id) => User.findById(id);
const findByEmail = (email) => User.findOne({ email });
const findBySepayKeyHash = (hash) => User.findOne({ sepayKeyHash: hash });
const create = (data) => User.create(data);
const save = (user) => user.save();
const verifyEmail = (emailVerifyTokenHash, now) =>
  User.findOneAndUpdate(
    { emailVerifyTokenHash, emailVerifyTokenExpires: { $gt: now }, emailVerified: false },
    { $set: { emailVerified: true, emailVerifyTokenHash: null, emailVerifyTokenExpires: null } },
    { new: true },
  );
const findByResetTokenHash = (resetTokenHash, now) =>
  User.findOne({ resetTokenHash, resetTokenExpires: { $gt: now }, emailVerified: true });
const resetPassword = (resetTokenHash, now, passwordHash) =>
  User.findOneAndUpdate(
    {
      resetTokenHash,
      resetTokenExpires: { $gt: now },
      emailVerified: true,
    },
    {
      $set: {
        passwordHash,
        resetTokenHash: null,
        resetTokenExpires: null,
        failedLogins: 0,
        lockUntil: null,
      },
      $inc: { tokenVersion: 1 },
    },
    { new: true },
  );

async function deleteWithData(userId) {
  await Promise.all(OWNED_MODELS.map((Model) => Model.deleteMany({ user: userId })));
  await User.deleteOne({ _id: userId });
}

module.exports = {
  findById,
  findByEmail,
  findBySepayKeyHash,
  create,
  save,
  verifyEmail,
  findByResetTokenHash,
  resetPassword,
  deleteWithData,
};
