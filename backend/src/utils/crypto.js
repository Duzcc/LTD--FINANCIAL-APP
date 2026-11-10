const crypto = require('crypto');

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = (bytes) => crypto.randomBytes(bytes).toString('base64url');
const sixDigitCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

module.exports = { sha256, randomToken, sixDigitCode };
