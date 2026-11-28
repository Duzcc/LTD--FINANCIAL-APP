const { badRequest } = require('../utils/errors');
const { CURRENCIES } = require('../domain/constants');

const EMAIL = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;
const NAME = /^[\p{L}][\p{L} .'-]*$/u;

function newEmail(value) {
  const email = String(value || '')
    .trim()
    .toLowerCase();
  if (!email) throw badRequest('Vui lòng nhập email.');
  if (email.length > 254 || email.split('@')[0].length > 64) throw badRequest('Email quá dài.');
  if (!EMAIL.test(email) || email.includes('..') || /^\.|\.@/.test(email)) throw badRequest('Email không hợp lệ.');
  return email;
}

function existingEmail(value) {
  const email = String(value || '')
    .trim()
    .toLowerCase();
  if (!email) throw badRequest('Vui lòng nhập email.');
  if (email.length > 254 || !email.includes('@')) throw badRequest('Email không hợp lệ.');
  return email;
}

function fullName(value) {
  const name = String(value || '')
    .trim()
    .replace(/\s+/g, ' ');
  if (!name) throw badRequest('Vui lòng nhập họ tên.');
  if (name.length < 2) throw badRequest('Họ tên phải có ít nhất 2 ký tự.');
  if (name.length > 50) throw badRequest('Họ tên tối đa 50 ký tự.');
  if (!NAME.test(name)) throw badRequest('Họ tên chỉ gồm chữ cái và khoảng trắng.');
  return name;
}

function newPassword(value, email = '', field = 'Mật khẩu') {
  const password = String(value || '');
  if (!password) throw badRequest(`Vui lòng nhập ${field.toLowerCase()}.`);
  if (password.length < 8) throw badRequest(`${field} phải có ít nhất 8 ký tự.`);
  if (Buffer.byteLength(password, 'utf8') > 72) throw badRequest(`${field} tối đa 72 byte khi mã hóa.`);
  if (/\s/.test(password)) throw badRequest(`${field} không được chứa khoảng trắng.`);
  if (!/\p{L}/u.test(password) || !/\d/.test(password)) throw badRequest(`${field} phải có cả chữ cái và chữ số.`);
  if (email && password.toLowerCase() === email) throw badRequest(`${field} không được trùng email.`);
  return password;
}

function actionToken(value) {
  const token = String(value || '').trim();
  if (!/^[A-Za-z0-9_-]{40,128}$/.test(token)) {
    throw badRequest('Liên kết không hợp lệ hoặc đã hết hạn.', 'INVALID_TOKEN');
  }
  return token;
}

function profile(body) {
  const changes = {};
  if (body.name !== undefined) changes.name = fullName(body.name);
  if (body.currency !== undefined) {
    if (!CURRENCIES.includes(body.currency)) throw badRequest('Đơn vị tiền tệ không được hỗ trợ.');
    changes.currency = body.currency;
  }
  if (body.hideBalance !== undefined) changes.hideBalance = body.hideBalance === true;
  if (body.rates && typeof body.rates === 'object') {
    changes.rates = Object.fromEntries(
      Object.entries(body.rates)
        .filter(
          ([currency, rate]) => CURRENCIES.includes(currency) && Number.isFinite(Number(rate)) && Number(rate) > 0,
        )
        .map(([currency, rate]) => [currency, Number(rate)]),
    );
  }
  return changes;
}

module.exports = { newEmail, existingEmail, fullName, newPassword, actionToken, profile };
