const ledger = require('../services/ledger.service');

module.exports = (name) => {
  const resource = ledger.resource(name);
  return {
    list: async (req, res) => res.json(await resource.list(req.user._id, req.query)),
    get: async (req, res) => res.json(await resource.get(req.user._id, req.params.id)),
    create: async (req, res) => res.status(201).json(await resource.create(req.user._id, req.body)),
    update: async (req, res) => {
      const { created, item } = await resource.update(req.user._id, req.params.id, req.body);
      res.status(created ? 201 : 200).json(item);
    },
    remove: async (req, res) => {
      await resource.remove(req.user._id, req.params.id, { cascade: req.query.cascade === 'true' });
      res.status(204).end();
    },
  };
};
