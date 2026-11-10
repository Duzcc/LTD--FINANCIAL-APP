const auth = require('../services/auth.service');

module.exports = {
  register: async (req, res) => res.status(201).json(await auth.register(req.body)),
  login: async (req, res) => res.json(await auth.login(req.body)),
  verifyOtp: async (req, res) => res.json(await auth.verifyOtp(req.body)),
  resendOtp: async (req, res) => res.json(await auth.resendOtp(req.body)),
  refresh: async (req, res) => res.json(await auth.refresh(req.body)),
  verifyEmail: async (req, res) => res.json(await auth.verifyEmail(req.user, req.body)),
  resendVerification: async (req, res) => res.json(await auth.resendVerification(req.user)),
  forgotPassword: async (req, res) => res.json(await auth.forgotPassword(req.body)),
  resetPassword: async (req, res) => res.json(await auth.resetPassword(req.body)),
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
