require('dotenv').config();
// Múi giờ dùng để xác định ngày/tháng khi tổng hợp báo cáo (mặc định giờ Việt Nam).
process.env.TZ = process.env.TZ || 'Asia/Ho_Chi_Minh';

const env = process.env.NODE_ENV || 'development';

const config = {
  env,
  isProduction: env === 'production',
  port: Number(process.env.PORT) || 3000,
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/finance_app',
  jwtSecret: process.env.JWT_SECRET || (env === 'production' ? '' : 'dev-only-secret-change-me'),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1h',
  refreshDays: Number(process.env.REFRESH_TOKEN_DAYS) || 30,
  ai: {
    provider: (process.env.AI_PROVIDER || '').toLowerCase(), // anthropic | openai | '' (tắt)
    apiKey: process.env.AI_API_KEY || process.env.ANTHROPIC_API_KEY || '',
    model: process.env.AI_MODEL || '',
    baseUrl: process.env.AI_BASE_URL || '',
    maxTokens: Number(process.env.AI_MAX_TOKENS) || 800,
  },
  // Dịch vụ AI riêng (Python/FastAPI). Để trống = backend tự xử lý bằng LLM trực tiếp/luật như trước.
  aiService: {
    url: (process.env.AI_SERVICE_URL || '').replace(/\/+$/, ''),
    key: process.env.AI_SERVICE_KEY || '',
    timeoutMs: Number(process.env.AI_SERVICE_TIMEOUT_MS) || 30000,
  },
  // Danh sách origin được phép gọi API (frontend chạy ở server khác). "*" = mọi origin.
  corsOrigins: (process.env.CORS_ORIGINS || '*').split(',').map((s) => s.trim()).filter(Boolean),
  resetCodeMinutes: Number(process.env.RESET_CODE_MINUTES) || 15,
  smtp: {
    host: process.env.SMTP_HOST || '',
    port: Number(process.env.SMTP_PORT) || 587,
    secure: process.env.SMTP_SECURE === 'true',
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    from: process.env.MAIL_FROM || 'Quản lý chi tiêu <no-reply@finance.local>',
  },
};

if (!config.jwtSecret) {
  throw new Error('JWT_SECRET bắt buộc khi NODE_ENV=production');
}

module.exports = config;
