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
function escapeHtml(value) {
  return String(value).replace(
    /[&<>"']/g,
    (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char],
  );
}

async function sendBrevo(to, subject, text, html) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: { 'api-key': config.smtp.brevoKey, 'content-type': 'application/json', accept: 'application/json' },
    body: JSON.stringify({ sender: sender(), to: [{ email: to }], subject, textContent: text, htmlContent: html }),
  });
  if (!res.ok) throw new Error(`Brevo từ chối gửi mail (${res.status}): ${await res.text()}`);
}

async function send(to, subject, text, html, devLabel, link) {
  if (config.smtp.brevoKey) {
    await sendBrevo(to, subject, text, html);
    return true;
  }
  if (!transport) {
    if (config.env === 'development') console.log(`[mail-dev] ${devLabel} cho ${to}: ${link}`);
    return false;
  }
  await transport.sendMail({ from: config.smtp.from, to, subject, text, html });
  return true;
}

function actionEmail(name, purpose, buttonLabel, appLink, webLink, emailLink) {
  const text = `Xin chào ${name},\n\n${purpose}\n\n${buttonLabel}: ${emailLink}\n\nNếu ứng dụng không tự mở, mở ứng dụng: ${appLink}\nHoặc tiếp tục trên trình duyệt:\n${webLink}`;
  const html = `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(buttonLabel)}</title></head><body style="font-family:Arial,sans-serif;line-height:1.6;color:#202124"><main style="max-width:560px;margin:32px auto;padding:24px"><p>Xin chào ${escapeHtml(name)},</p><p>${escapeHtml(purpose)}</p><p style="margin:28px 0"><a href="${escapeHtml(emailLink)}" style="background:#16834a;border-radius:8px;color:#fff;display:inline-block;padding:12px 20px;text-decoration:none;font-weight:bold">${escapeHtml(buttonLabel)}</a></p><p>Nếu ứng dụng không tự mở, <a href="${escapeHtml(appLink)}">mở ứng dụng</a> hoặc <a href="${escapeHtml(webLink)}">tiếp tục trên trình duyệt</a>.</p><p>Nếu bạn không yêu cầu thao tác này, hãy bỏ qua email.</p></main></body></html>`;
  return { text, html };
}

const sendResetLink = (email, name, appLink, webLink, emailLink) => {
  const content = actionEmail(
    name,
    `Nhấn nút bên dưới để đặt mật khẩu mới. Liên kết có hiệu lực trong ${config.resetTokenMinutes} phút và chỉ dùng một lần.`,
    'Xác nhận đặt lại mật khẩu',
    appLink,
    webLink,
    emailLink,
  );
  return send(
    email,
    'Đặt lại mật khẩu – Quản lý chi tiêu',
    content.text,
    content.html,
    'Liên kết đặt lại mật khẩu',
    emailLink,
  );
};

const sendVerificationLink = (email, name, appLink, webLink, emailLink) => {
  const content = actionEmail(
    name,
    `Nhấn nút bên dưới để xác minh email và hoàn tất đăng ký. Liên kết có hiệu lực trong ${Math.floor(config.emailVerifyMinutes / 60)} giờ.`,
    'Xác nhận email',
    appLink,
    webLink,
    emailLink,
  );
  return send(
    email,
    'Xác thực email – Quản lý chi tiêu',
    content.text,
    content.html,
    'Liên kết xác minh email',
    emailLink,
  );
};

module.exports = { mailEnabled, sendResetLink, sendVerificationLink };
