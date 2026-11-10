const router = require('express').Router();
const ai = require('../controllers/ai.controller');
const asyncHandler = require('../middleware/async-handler');
const { aiLimiter } = require('../middleware/rate-limit');

router.use(aiLimiter);
router.get('/status', asyncHandler(ai.status));
router.post('/chat', asyncHandler(ai.chat));
router.post('/categorize', asyncHandler(ai.categorize));
router.post('/parse', asyncHandler(ai.parse));
router.get('/forecast', asyncHandler(ai.forecast));
router.get('/anomalies', asyncHandler(ai.anomalies));
router.get('/budgets/recommend', asyncHandler(ai.recommendBudgets));
router.get('/insights', asyncHandler(ai.insights));
router.post('/search', asyncHandler(ai.search));
router.post('/receipts/text', asyncHandler(ai.receiptFromText));
router.post('/receipts/scan', asyncHandler(ai.receiptFromImage));

module.exports = router;
