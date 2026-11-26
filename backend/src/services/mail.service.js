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

const mailEnabled = () => transport !== null || Boolean(config.smtp.brevoKey);

function sender() {
  const m = config.smtp.from.match(/^(.*)<(.+)>$/);
  return m ? { name: m[1].trim(), email: m[2].trim() } : { email: config.smtp.from };
}

// máy chủ miễn phí (Render, Railway) chặn cổng SMTP nên gửi qua API HTTP của Brevo
async function sendBrevo(to, subject, text) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': config.smtp.brevoKey, 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: sender(), to: [{ email: to }], subject, textContent: text }),
  });
  if (!res.ok) throw new Error(`Brevo từ chối gửi mail (${res.status}): ${await res.text()}`);
}

async function send(to, subject, text, devLabel, code) {
  if (config.smtp.brevoKey) {
    await sendBrevo(to, subject, text);
    return true;
  }
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
