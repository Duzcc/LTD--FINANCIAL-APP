const sync = require('../services/sync.service');

module.exports = {
  snapshot: async (req, res) => res.json(await sync.snapshot(req.user)),
  batch: async (req, res) => {
    const { status, body } = await sync.applyBatch(req.user._id, req.body.ops);
    res.status(status).json(body);
  },
};
