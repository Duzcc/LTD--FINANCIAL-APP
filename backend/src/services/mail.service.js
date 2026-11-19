const nodemailer = require('nodemailer');
const config = require('../config');

const transport = config.smtp.host
  ? nodemailer.createTransport({
      host: config.smtp.host,
      port: config.smtp.port,
      secure: config.smtp.secure,
      auth: config.smtp.user ? { user: config.smtp.user, pass: config.smtp.pass } : undefined,
    })
  : null;

const mailEnabled = () => transport !== null;

async function send(to, subject, text, devLabel, code) {
  if (!transport) {
    if (config.env === 'development') console.log(`[mail-dev] ${devLabel} cho ${to}: ${code}`);
    return false;
  }
  await transport.sendMail({ from: config.smtp.from, to, subject, text });
  return true;
}

const sendResetCode = (email, name, code) =>
  send(
    email,
    'Mã khôi phục mật khẩu – Quản lý chi tiêu',
    `Xin chào ${name},\n\nMã khôi phục mật khẩu của bạn là: ${code}\nMã có hiệu lực trong ${config.resetCodeMinutes} phút.\n\nNếu bạn không yêu cầu, hãy bỏ qua email này.`,
    'Mã khôi phục',
    code,
  );

const sendVerifyCode = (email, name, code) =>
  send(
    email,
    'Xác thực email – Quản lý chi tiêu',
    `Xin chào ${name},\n\nMã xác thực email của bạn là: ${code}\nMã có hiệu lực trong 24 giờ.`,
    'Mã xác thực email',
    code,
  );

function sendOtpCode(email, name, code, purpose) {
  const action = purpose === 'register' ? 'hoàn tất đăng ký' : 'đăng nhập';
  return send(
    email,
    `Mã OTP ${action} – Quản lý chi tiêu`,
    `Xin chào ${name},\n\nMã OTP để ${action} của bạn là: ${code}\nMã có hiệu lực trong ${config.otp.minutes} phút. Tuyệt đối không chia sẻ mã này cho người khác.\n\nNếu không phải bạn, hãy đổi mật khẩu ngay.`,
    `Mã OTP ${action}`,
    code,
  );
}

module.exports = { mailEnabled, sendResetCode, sendVerifyCode, sendOtpCode };
