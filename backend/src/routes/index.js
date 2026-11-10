const router = require('express').Router();
const { requireAuth } = require('../middleware/auth');
const { RESOURCES } = require('../services/ledger.service');
const resourceRoutes = require('./resource.routes');

router.use('/auth', require('./auth.routes'));
for (const name of RESOURCES) router.use(`/${name}`, requireAuth, resourceRoutes(name));
router.use('/reports', requireAuth, require('./report.routes'));
router.use('/sync', requireAuth, require('./sync.routes'));
router.use('/ai', requireAuth, require('./ai.routes'));
router.use('/bank', require('./bank.routes'));

module.exports = router;
