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
// Mã OTP đăng nhập / xác thực đăng ký
async function sendOtpCode(email, name, code, purpose) {
  const action = purpose === 'register' ? 'hoàn tất đăng ký' : 'đăng nhập';
  if (!transport) {
    if (config.env === 'development') console.log(`[mail-dev] Mã OTP ${action} cho ${email}: ${code}`);
    return false;
  }
  await transport.sendMail({
    from: config.smtp.from,
    to: email,
    subject: `Mã OTP ${action} – Quản lý chi tiêu`,
    text: `Xin chào ${name},\n\nMã OTP để ${action} của bạn là: ${code}\nMã có hiệu lực trong ${config.otp.minutes} phút. Tuyệt đối không chia sẻ mã này cho người khác.\n\nNếu không phải bạn, hãy đổi mật khẩu ngay.`,
  });
  return true;
}
module.exports = { sendResetCode, sendVerifyCode, sendOtpCode, mailEnabled };
