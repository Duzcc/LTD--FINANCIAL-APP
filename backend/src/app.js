const path = require('node:path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const mongoose = require('mongoose');
const config = require('./config');
const routes = require('./routes');
const { notFoundRoute, errorHandler } = require('./middleware/error');

const RECEIPT_SCAN_PATH = '/api/ai/receipts/scan';
const jsonBody = express.json({ limit: '2mb' });
const receiptBody = express.json({ limit: '9mb' });

const app = express();
app.set('trust proxy', 1);
app.use(helmet());
app.use(
  cors({
    origin: config.corsOrigins.includes('*') ? true : config.corsOrigins,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-Id'],
  }),
);
app.use((req, res, next) => (req.path === RECEIPT_SCAN_PATH ? receiptBody : jsonBody)(req, res, next));
if (config.env !== 'test') app.use(morgan(config.isProduction ? 'combined' : 'dev'));

app.get('/', (_req, res) =>
  res.json({ name: 'Finance App API', version: require('../package.json').version, docs: '/api/openapi.yaml' }),
);
app.get('/api/openapi.yaml', (_req, res) =>
  res.type('text/yaml').sendFile(path.join(__dirname, '..', 'docs', 'openapi.yaml')),
);
app.get('/api/health', (_req, res) =>
  res.json({
    status: 'ok',
    db: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
    time: new Date().toISOString(),
  }),
);
app.use('/api', routes);

app.use(notFoundRoute);
app.use(errorHandler);

module.exports = app;
