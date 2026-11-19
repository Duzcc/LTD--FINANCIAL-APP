const { badRequest } = require('../utils/errors');

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

function requiredText(value, field, max = 500) {
  if (typeof value !== 'string' || !value.trim()) throw badRequest(`Thiếu ${field}.`);
  return value.trim().slice(0, max);
}

function chatMessages(messages) {
  if (!Array.isArray(messages) || messages.length === 0) throw badRequest('Thiếu nội dung câu hỏi.');
  const list = messages
    .slice(-12)
    .map((m) => ({
      role: m?.role === 'assistant' ? 'assistant' : 'user',
      content: String(m?.content || '').slice(0, 2000),
    }))
    .filter((m) => m.content.trim());
  while (list.length && list[0].role !== 'user') list.shift();
  if (!list.length || list[list.length - 1].role !== 'user') throw badRequest('Tin nhắn cuối phải là câu hỏi.');
  return list;
}

function budgetQuery(query) {
  const savingsRate = query.savingsRate == null ? 0.2 : Number(query.savingsRate);
  if (!(savingsRate >= 0 && savingsRate <= 0.6)) throw badRequest('savingsRate phải trong khoảng 0–0.6.');
  const monthlyIncome = query.monthlyIncome == null ? null : Number(query.monthlyIncome);
  return { savingsRate, monthlyIncome };
}

function receiptImage(body) {
  const { image, mediaType = 'image/jpeg' } = body || {};
  if (typeof image !== 'string' || !image) throw badRequest('Thiếu ảnh hóa đơn.');
  if (!IMAGE_TYPES.includes(mediaType)) throw badRequest('Chỉ hỗ trợ ảnh JPEG/PNG/WebP.');
  const bytes = Buffer.from(image, 'base64');
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) throw badRequest('Ảnh rỗng hoặc lớn hơn 6MB.');
  return { bytes, mediaType };
}

module.exports = { requiredText, chatMessages, budgetQuery, receiptImage };
