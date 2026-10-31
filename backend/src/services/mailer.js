const nodemailer = require('nodemailer');
const config = require('../config');

let transport = null;
if (config.smtp.host) {
  transport = nodemailer.createTransport({
    host: config.smtp.host, port: config.smtp.port, secure: config.smtp.secure,
    auth: config.smtp.user ? { user: config.smtp.user, pass: config.smtp.pass } : undefined,
  });
}

const mailEnabled = () => transport !== null;

async function sendResetCode(email, name, code) {
  if (!transport) {
    if (config.env === 'development') console.log(`[mail-dev] Mã khôi phục cho ${email}: ${code}`);
    return false;
  }
  await transport.sendMail({
    from: config.smtp.from,
    to: email,
    subject: 'Mã khôi phục mật khẩu – Quản lý chi tiêu',
    text: `Xin chào ${name},\n\nMã khôi phục mật khẩu của bạn là: ${code}\nMã có hiệu lực trong ${config.resetCodeMinutes} phút.\n\nNếu bạn không yêu cầu, hãy bỏ qua email này.`,
  });
  return true;
}
async function sendVerifyCode(email, name, code) {
  if (!transport) {
    if (config.env === 'development') console.log(`[mail-dev] Mã xác thực email cho ${email}: ${code}`);
    return false;
  }
  await transport.sendMail({
    from: config.smtp.from,
    to: email,
    subject: 'Xác thực email – Quản lý chi tiêu',
    text: `Xin chào ${name},\n\nMã xác thực email của bạn là: ${code}\nMã có hiệu lực trong 24 giờ.`,
  });
  return true;
}
module.exports = { sendResetCode, sendVerifyCode, mailEnabled };
