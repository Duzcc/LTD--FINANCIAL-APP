const router = require('express').Router();
const bank = require('../controllers/bank.controller');
const asyncHandler = require('../middleware/async-handler');
const { requireAuth } = require('../middleware/auth');
const { webhookLimiter } = require('../middleware/rate-limit');

router.get('/banks', bank.banks);
router.post('/sepay/webhook', webhookLimiter, asyncHandler(bank.webhook));

router.get('/sepay', requireAuth, bank.sepayStatus);
router.post('/sepay/key', requireAuth, asyncHandler(bank.createWebhookKey));
router.delete('/sepay/key', requireAuth, asyncHandler(bank.revokeWebhookKey));
router.get('/requests', requireAuth, asyncHandler(bank.listRequests));
router.get('/requests/:id', requireAuth, asyncHandler(bank.getRequest));
router.post('/requests', requireAuth, asyncHandler(bank.createRequest));
router.delete('/requests/:id', requireAuth, asyncHandler(bank.cancelRequest));

module.exports = router;
