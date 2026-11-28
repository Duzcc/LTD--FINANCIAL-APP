const crypto = require('crypto');

const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const randomToken = (bytes) => crypto.randomBytes(bytes).toString('base64url');

module.exports = { sha256, randomToken };
