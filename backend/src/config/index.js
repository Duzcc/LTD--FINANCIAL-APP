if (process.env.NODE_ENV !== 'test') require('dotenv').config();
process.env.TZ = process.env.TZ || 'Asia/Ho_Chi_Minh';

const env = process.env.NODE_ENV || 'development';
const trimSlash = (value) => (value || '').replace(/\/+$/, '');

const config = {
  env,
  isProduction: env === 'production',
  port: Number(process.env.PORT) || 3000,
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/finance_app',
  mongoDb: process.env.MONGODB_DB || '',
  jwtSecret: process.env.JWT_SECRET || (env === 'production' ? '' : 'dev-only-secret-change-me'),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1h',
  refreshDays: Number(process.env.REFRESH_TOKEN_DAYS) || 30,
  corsOrigins: (process.env.CORS_ORIGINS || '*')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  publicUrl: trimSlash(process.env.PUBLIC_URL),
  paymentRequestDays: Number(process.env.PAYMENT_REQUEST_DAYS) || 7,
  resetCodeMinutes: Number(process.env.RESET_CODE_MINUTES) || 15,
  maxFailedLogins: Number(process.env.MAX_FAILED_LOGINS) || 5,
  lockMinutes: Number(process.env.LOGIN_LOCK_MINUTES) || 15,
  otp: {
    minutes: Number(process.env.OTP_MINUTES) || 5,
    resendSeconds: Number(process.env.OTP_RESEND_SECONDS) || 60,
    maxAttempts: 5,
    maxSends: 5,
  },
  rateLimits: {
    auth: Number(process.env.AUTH_RATE_LIMIT) || 50,
    ai: Number(process.env.AI_RATE_LIMIT) || 30,
    webhook: Number(process.env.WEBHOOK_RATE_LIMIT) || 120,
  },
  ai: {
    provider: (process.env.AI_PROVIDER || '').toLowerCase(),
    apiKey: process.env.AI_API_KEY || process.env.ANTHROPIC_API_KEY || '',
    model: process.env.AI_MODEL || '',
    baseUrl: process.env.AI_BASE_URL || '',
    maxTokens: Number(process.env.AI_MAX_TOKENS) || 800,
  },
  aiService: {
    url: trimSlash(process.env.AI_SERVICE_URL),
    key: process.env.AI_SERVICE_KEY || '',
    timeoutMs: Number(process.env.AI_SERVICE_TIMEOUT_MS) || 30000,
  },
  sepay: {
    apiToken: process.env.SEPAY_API_TOKEN || '',
    apiUrl: trimSlash(process.env.SEPAY_API_URL || 'https://my.sepay.vn/userapi'),
    pollSeconds: Math.max(5, Number(process.env.SEPAY_POLL_SECONDS) || 15),
    ownerEmail: (process.env.SEPAY_OWNER_EMAIL || '').trim().toLowerCase(),
    minGapMs: 3000,
  },
  smtp: {
    host: process.env.SMTP_HOST || '',
    port: Number(process.env.SMTP_PORT) || 587,
    secure: process.env.SMTP_SECURE === 'true',
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    from: process.env.MAIL_FROM || 'Quản lý chi tiêu <no-reply@finance.local>',
  },
};

if (!config.mongoDb) {
  const dbInUri = (config.mongoUri.split('?')[0].match(/^mongodb(?:\+srv)?:\/\/[^/]+\/(.*)$/) || [])[1];
  config.mongoDb = dbInUri || 'finance_app';
}

if (!config.jwtSecret) throw new Error('JWT_SECRET bắt buộc khi NODE_ENV=production');

module.exports = config;
