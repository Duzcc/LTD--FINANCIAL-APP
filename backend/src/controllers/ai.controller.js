const ai = require('../services/ai.service');

const requestId = (req) => req.get('x-request-id');

module.exports = {
  status: async (_req, res) => res.json(await ai.status()),
  chat: async (req, res) => res.json(await ai.chat(req.user, req.body, requestId(req))),
  categorize: async (req, res) => res.json(await ai.categorize(req.user, req.body, requestId(req))),
  parse: async (req, res) => res.json(await ai.parse(req.user, req.body, requestId(req))),
  forecast: async (req, res) => res.json(await ai.forecast(req.user, requestId(req))),
  anomalies: async (req, res) => res.json(await ai.anomalies(req.user, requestId(req))),
  recommendBudgets: async (req, res) => res.json(await ai.recommendBudgets(req.user, req.query, requestId(req))),
  insights: async (req, res) => res.json(await ai.insights(req.user, requestId(req))),
  search: async (req, res) => res.json(await ai.search(req.user, req.body, requestId(req))),
  receiptFromText: async (req, res) => res.json(await ai.receiptFromText(req.user, req.body, requestId(req))),
  receiptFromImage: async (req, res) => res.json(await ai.receiptFromImage(req.user, req.body, requestId(req))),
};
