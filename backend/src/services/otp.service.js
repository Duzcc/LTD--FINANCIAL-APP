const bcrypt = require('bcryptjs');
const config = require('../config');
const otps = require('../repositories/otp.repository');
const { sendOtpCode, mailEnabled } = require('./mail.service');
const { sha256, randomToken, sixDigitCode } = require('../utils/crypto');
const { badRequest, tooMany } = require('../utils/errors');

const PURGE_AFTER_MS = 3600000;
const TOO_MANY_ATTEMPTS = 'Bạn đã nhập sai quá nhiều lần, vui lòng đăng nhập lại.';

const expired = () => badRequest('Phiên xác thực đã hết hạn, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
const devCode = (sent, code) => (!sent && !config.isProduction ? code : undefined);

async function start(user, purpose, pending = {}) {
  const otpToken = randomToken(32);
  const code = sixDigitCode();
  const now = Date.now();
  await otps.replace(user._id, purpose, {
    tokenHash: sha256(otpToken),
    codeHash: await bcrypt.hash(code, 8),
    expiresAt: new Date(now + config.otp.minutes * 60000),
    lastSentAt: new Date(now),
    purgeAt: new Date(now + PURGE_AFTER_MS),
    ...pending,
  });
  const sent = await sendOtpCode(user.email, pending.pendingName || user.name, code, purpose);
  return {
    otpRequired: true,
    otpToken,
    purpose,
    email: user.email,
    expiresIn: config.otp.minutes * 60,
    resendAfter: config.otp.resendSeconds,
    mailEnabled: mailEnabled(),
    devCode: devCode(sent, code),
  };
}

async function find(rawToken) {
  const token = String(rawToken || '');
  const challenge = token ? await otps.findByTokenHash(sha256(token)) : null;
  if (!challenge) throw expired();
  return challenge;
}

async function verify(challenge, code) {
  if (challenge.expiresAt < new Date()) {
    throw badRequest('Mã OTP đã hết hạn, hãy bấm "Gửi lại mã".', 'OTP_EXPIRED_CODE');
  }
  const counted = await otps.countAttempt(challenge._id, config.otp.maxAttempts);
  if (!counted) throw badRequest(TOO_MANY_ATTEMPTS, 'OTP_EXPIRED');
  if (!(await bcrypt.compare(code, challenge.codeHash))) {
    const left = config.otp.maxAttempts - counted.attempts;
    if (left <= 0) {
      await otps.consume(challenge._id);
      throw badRequest(TOO_MANY_ATTEMPTS, 'OTP_EXPIRED');
    }
    throw badRequest(`Mã OTP không đúng. Bạn còn ${left} lần thử.`, 'INVALID_CODE');
  }
  if (!(await otps.consume(challenge._id))) throw expired();
}

async function resend(challenge, user) {
  const wait = Math.ceil((challenge.lastSentAt.getTime() + config.otp.resendSeconds * 1000 - Date.now()) / 1000);
  if (wait > 0) throw tooMany(`Vui lòng đợi ${wait} giây trước khi gửi lại mã.`, 'OTP_RESEND_WAIT');
  if (challenge.sends >= config.otp.maxSends) {
    await otps.consume(challenge._id);
    throw tooMany('Bạn đã yêu cầu gửi lại mã quá nhiều lần, vui lòng đăng nhập lại.', 'OTP_EXPIRED');
  }
  const code = sixDigitCode();
  const now = Date.now();
  Object.assign(challenge, {
    codeHash: await bcrypt.hash(code, 8),
    expiresAt: new Date(now + config.otp.minutes * 60000),
    attempts: 0,
    sends: challenge.sends + 1,
    lastSentAt: new Date(now),
    purgeAt: new Date(now + PURGE_AFTER_MS),
  });
  await otps.save(challenge);
  const sent = await sendOtpCode(user.email, user.name, code, challenge.purpose);
  return {
    message: 'Đã gửi lại mã OTP.',
    expiresIn: config.otp.minutes * 60,
    resendAfter: config.otp.resendSeconds,
    devCode: devCode(sent, code),
  };
}

module.exports = { start, find, verify, resend, expired, devCode };
