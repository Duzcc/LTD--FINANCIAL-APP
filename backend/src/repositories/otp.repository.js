const { OtpChallenge } = require('../models');

async function replace(user, purpose, data) {
  await OtpChallenge.deleteMany({ user, purpose });
  return OtpChallenge.create({ user, purpose, ...data });
}

const findByTokenHash = (tokenHash) => OtpChallenge.findOne({ tokenHash });
const countAttempt = (id, maxAttempts) =>
  OtpChallenge.findOneAndUpdate({ _id: id, attempts: { $lt: maxAttempts } }, { $inc: { attempts: 1 } }, { new: true });
const consume = async (id) => (await OtpChallenge.deleteOne({ _id: id })).deletedCount > 0;
const save = (challenge) => challenge.save();

module.exports = { replace, findByTokenHash, countAttempt, consume, save };
