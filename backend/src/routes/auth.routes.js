const router = require('express').Router();
const auth = require('../controllers/auth.controller');
const asyncHandler = require('../middleware/async-handler');
const { requireAuth } = require('../middleware/auth');
const { authLimiter } = require('../middleware/rate-limit');

router.use((_req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

router.post('/register', authLimiter, asyncHandler(auth.register));
router.post('/login', authLimiter, asyncHandler(auth.login));
router.post('/refresh', authLimiter, asyncHandler(auth.refresh));
router.post('/forgot-password', authLimiter, asyncHandler(auth.forgotPassword));
router.get('/open-app/:action', asyncHandler(auth.openAuthApp));
router.post('/reset-password/validate', authLimiter, asyncHandler(auth.validateResetToken));
router.get('/reset-password', asyncHandler(auth.resetPasswordPage));
router.post('/reset-password', authLimiter, asyncHandler(auth.resetPassword));
router.get('/verify-email', asyncHandler(auth.verifyEmailPage));
router.post('/verify-email', authLimiter, asyncHandler(auth.verifyEmail));
router.post('/resend-verification', authLimiter, asyncHandler(auth.resendVerification));
router.get('/me', requireAuth, auth.me);
router.put('/me', requireAuth, asyncHandler(auth.updateProfile));
router.delete('/me', requireAuth, asyncHandler(auth.deleteAccount));
router.put('/change-password', requireAuth, authLimiter, asyncHandler(auth.changePassword));
router.post('/logout', requireAuth, asyncHandler(auth.logout));

module.exports = router;
