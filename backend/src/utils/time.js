const VN_OFFSET_MS = 7 * 3600000;

function localIso(d = new Date()) {
  const offset = -d.getTimezoneOffset();
  const sign = offset >= 0 ? '+' : '-';
  const pad = (n) => String(Math.trunc(Math.abs(n))).padStart(2, '0');
  const local = new Date(d.getTime() + offset * 60000).toISOString().slice(0, 19);
  return `${local}${sign}${pad(offset / 60)}:${pad(offset % 60)}`;
}

const parseVnDateTime = (value) => (value ? new Date(`${String(value).replace(' ', 'T')}+07:00`) : null);
const formatVnDateTime = (d) => new Date(d.getTime() + VN_OFFSET_MS).toISOString().slice(0, 19).replace('T', ' ');

module.exports = { localIso, parseVnDateTime, formatVnDateTime };
