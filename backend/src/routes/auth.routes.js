const router = require('express').Router();
const auth = require('../controllers/auth.controller');
const asyncHandler = require('../middleware/async-handler');
const { requireAuth } = require('../middleware/auth');
const { authLimiter } = require('../middleware/rate-limit');

router.post('/register', authLimiter, asyncHandler(auth.register));
router.post('/login', authLimiter, asyncHandler(auth.login));
router.post('/verify-otp', authLimiter, asyncHandler(auth.verifyOtp));
router.post('/resend-otp', authLimiter, asyncHandler(auth.resendOtp));
router.post('/refresh', authLimiter, asyncHandler(auth.refresh));
router.post('/forgot-password', authLimiter, asyncHandler(auth.forgotPassword));
router.post('/reset-password', authLimiter, asyncHandler(auth.resetPassword));

router.post('/verify-email', requireAuth, authLimiter, asyncHandler(auth.verifyEmail));
router.post('/resend-verification', requireAuth, authLimiter, asyncHandler(auth.resendVerification));
router.get('/me', requireAuth, auth.me);
router.put('/me', requireAuth, asyncHandler(auth.updateProfile));
router.delete('/me', requireAuth, asyncHandler(auth.deleteAccount));
router.put('/change-password', requireAuth, authLimiter, asyncHandler(auth.changePassword));
router.post('/logout', requireAuth, asyncHandler(auth.logout));

module.exports = router;
