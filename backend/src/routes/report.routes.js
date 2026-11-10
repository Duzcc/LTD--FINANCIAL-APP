const router = require('express').Router();
const reports = require('../controllers/report.controller');
const asyncHandler = require('../middleware/async-handler');

router.get('/dashboard', asyncHandler(reports.dashboard));
router.get('/summary', asyncHandler(reports.summary));
router.get('/debts', asyncHandler(reports.debts));

module.exports = router;
