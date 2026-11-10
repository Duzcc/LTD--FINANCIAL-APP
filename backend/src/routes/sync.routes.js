const router = require('express').Router();
const sync = require('../controllers/sync.controller');
const asyncHandler = require('../middleware/async-handler');

router.get('/', asyncHandler(sync.snapshot));
router.post('/batch', asyncHandler(sync.batch));

module.exports = router;
