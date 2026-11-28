const auth = require('../services/auth.service');
const validate = require('../validators/auth.validator');
const config = require('../config');
const { badRequest } = require('../utils/errors');

const escapeHtml = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char],
  );

function page(title, content) {
  return `<!doctype html><html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title><main><h1>${escapeHtml(title)}</h1>${content}</main></html>`;
}

function verifyPage(token, error = '') {
  return page(
    'Xác minh email',
    `${error ? `<p role="alert">${escapeHtml(error)}</p>` : '<p>Nhấn nút bên dưới để xác minh email và hoàn tất đăng ký.</p>'}<form method="post" action="/api/auth/verify-email"><input type="hidden" name="token" value="${escapeHtml(token)}"><button type="submit">Xác minh email</button></form>`,
  );
}

function resetPage(token, error = '') {
  return page(
    'Đặt lại mật khẩu',
    `${error ? `<p role="alert">${escapeHtml(error)}</p>` : '<p>Nhập mật khẩu mới của bạn.</p>'}<form method="post" action="/api/auth/reset-password"><input type="hidden" name="token" value="${escapeHtml(token)}"><label>Mật khẩu mới <input type="password" name="newPassword" autocomplete="new-password" minlength="8" maxlength="72" required></label><p>Mật khẩu tối thiểu 8 ký tự, gồm chữ và số, không chứa khoảng trắng.</p><label>Nhập lại mật khẩu <input type="password" name="confirmPassword" autocomplete="new-password" minlength="8" maxlength="72" required></label><button type="submit">Lưu mật khẩu mới</button></form>`,
  );
}

function openAppPage(action, token) {
  const appLink = `financeapp://auth/${action}?token=${encodeURIComponent(token)}`;
  const base = config.publicUrl || `http://localhost:${config.port}`;
  const webLink = `${base}/api/auth/${action}?token=${encodeURIComponent(token)}`;
  return page(
    'Đang mở ứng dụng',
    `<p>Đang mở ứng dụng Quản lý chi tiêu…</p><p><a href="${escapeHtml(appLink)}">Mở ứng dụng</a></p><p>Nếu chưa cài ứng dụng, <a href="${escapeHtml(webLink)}">tiếp tục trên trình duyệt</a>.</p><script>window.location.replace(${JSON.stringify(appLink)});</script>`,
  );
}

module.exports = {
  register: async (req, res) => res.status(201).json(await auth.register(req.body)),
  login: async (req, res) => res.json(await auth.login(req.body)),
  refresh: async (req, res) => res.json(await auth.refresh(req.body)),
  verifyEmailPage: (req, res) => {
    const token = validate.actionToken(req.query.token);
    res.type('html').send(verifyPage(token));
  },
  openAuthApp: (req, res) => {
    const action = req.params.action;
    if (!['verify-email', 'reset-password'].includes(action)) {
      throw badRequest('Liên kết email không hợp lệ.', 'INVALID_EMAIL_ACTION');
    }
    const token = validate.actionToken(req.query.token);
    res.type('html').send(openAppPage(action, token));
  },
  verifyEmail: async (req, res) => {
    try {
      const result = await auth.verifyEmail(req.body.token);
      if (req.is('application/x-www-form-urlencoded')) {
        return res.type('html').send(page('Email đã xác minh', '<p>Bạn có thể quay lại ứng dụng để đăng nhập.</p>'));
      }
      return res.json(result);
    } catch (error) {
      if (req.is('application/x-www-form-urlencoded') && error.status) {
        return res
          .status(error.status)
          .type('html')
          .send(verifyPage(req.body.token || '', error.message));
      }
      throw error;
    }
  },
  resendVerification: async (req, res) => res.json(await auth.resendVerification(req.body)),
  forgotPassword: async (req, res) => res.json(await auth.forgotPassword(req.body)),
  validateResetToken: async (req, res) => {
    await auth.validateResetToken(req.body.token);
    res.json({ valid: true });
  },
  resetPasswordPage: async (req, res) => {
    try {
      const token = validate.actionToken(req.query.token);
      await auth.validateResetToken(token);
      return res.type('html').send(resetPage(token));
    } catch (error) {
      if (!error.status) throw error;
      return res
        .status(error.status)
        .type('html')
        .send(
          page(
            'Liên kết không hợp lệ',
            `<p role="alert">${escapeHtml(error.message)}</p><p>Hãy yêu cầu một liên kết đặt lại mật khẩu mới trong ứng dụng.</p>`,
          ),
        );
    }
  },
  resetPassword: async (req, res) => {
    try {
      const result = await auth.resetPassword(req.body);
      if (req.is('application/x-www-form-urlencoded')) {
        return res
          .type('html')
          .send(page('Đã cập nhật mật khẩu', '<p>Bạn có thể quay lại ứng dụng để đăng nhập bằng mật khẩu mới.</p>'));
      }
      return res.json(result);
    } catch (error) {
      if (req.is('application/x-www-form-urlencoded') && error.status) {
        return res
          .status(error.status)
          .type('html')
          .send(resetPage(req.body.token || '', error.message));
      }
      throw error;
    }
  },
  me: (req, res) => res.json({ user: req.user.toJSON() }),
  updateProfile: async (req, res) => res.json(await auth.updateProfile(req.user, req.body)),
  changePassword: async (req, res) => res.json(await auth.changePassword(req.user, req.body)),
  logout: async (req, res) => {
    await auth.logout(req.user, req.sessionId, req.body);
    res.status(204).end();
  },
  deleteAccount: async (req, res) => {
    await auth.deleteAccount(req.user, req.body);
    res.status(204).end();
  },
};
