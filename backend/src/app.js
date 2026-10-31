const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const mongoose = require('mongoose');
const config = require('./config');
const { requireAuth } = require('./middleware/auth');
const { notFoundRoute, errorHandler } = require('./middleware/error');
const { resourceRouter } = require('./routes/resources');

const app = express();
app.set('trust proxy', 1);
app.use(helmet());
// Frontend (app Flutter / web) chạy ở server khác → cho phép CORS theo cấu hình.
app.use(cors({
  origin: config.corsOrigins.includes('*') ? true : config.corsOrigins,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-Id'],
}));
const jsonSmall = express.json({ limit: '2mb' });
const jsonLarge = express.json({ limit: '9mb' }); // ảnh hóa đơn (base64)
app.use((req, res, next) => (req.path === '/api/ai/receipts/scan' ? jsonLarge : jsonSmall)(req, res, next));
if (config.env !== 'test') app.use(morgan(config.isProduction ? 'combined' : 'dev'));

app.get('/', (_req, res) => res.json({ name: 'Finance App API', version: '1.1.0', docs: '/api/openapi.yaml' }));
app.get('/api/openapi.yaml', (_req, res) => res.type('text/yaml').sendFile(require('node:path').join(__dirname, '..', 'docs', 'openapi.yaml')));
app.get('/api/health', (_req, res) =>
  res.json({ status: 'ok', db: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected', time: new Date().toISOString() }));

app.use('/api/auth', require('./routes/auth'));
for (const r of ['wallets', 'categories', 'people', 'transactions', 'budgets', 'recurring']) {
  app.use(`/api/${r}`, requireAuth, resourceRouter(r));
}
app.use('/api/reports', requireAuth, require('./routes/reports'));
app.use('/api/sync', requireAuth, require('./routes/sync'));
app.use('/api/ai', requireAuth, require('./routes/ai'));

app.use(notFoundRoute);
app.use(errorHandler);
module.exports = app;
