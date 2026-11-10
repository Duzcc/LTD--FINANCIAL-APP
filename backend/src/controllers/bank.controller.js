const config = require('../config');
const bank = require('../services/bank.service');
const { BANKS } = require('../domain/banks');

const webhookUrl = (req) => `${config.publicUrl || `${req.protocol}://${req.get('host')}`}/api/bank/sepay/webhook`;

module.exports = {
  banks: (_req, res) => res.json({ items: BANKS }),
  sepayStatus: (req, res) => res.json(bank.sepayStatus(req.user, webhookUrl(req))),
  createWebhookKey: async (req, res) => res.status(201).json(await bank.createWebhookKey(req.user, webhookUrl(req))),
  revokeWebhookKey: async (req, res) => {
    await bank.revokeWebhookKey(req.user);
    res.status(204).end();
  },
  listRequests: async (req, res) => res.json(await bank.listRequests(req.user, req.query)),
  getRequest: async (req, res) => res.json(await bank.getRequest(req.user, req.params.id)),
  createRequest: async (req, res) => res.status(201).json(await bank.createRequest(req.user, req.body)),
  cancelRequest: async (req, res) => res.json(await bank.cancelRequest(req.user, req.params.id)),
  webhook: async (req, res) => res.json({ success: true, ...(await bank.handleWebhook(req.headers.authorization, req.body)) }),
};
