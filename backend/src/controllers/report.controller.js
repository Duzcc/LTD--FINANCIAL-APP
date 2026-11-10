const reports = require('../services/report.service');

module.exports = {
  dashboard: async (req, res) => res.json(await reports.dashboard(req.user, req.query)),
  summary: async (req, res) => res.json(await reports.summary(req.user, req.query)),
  debts: async (req, res) => res.json(await reports.debts(req.user, req.query)),
};
