// Chạy backend với MongoDB nhúng (mongodb-memory-server) để demo nhanh khi máy chưa cài MongoDB.
// Dữ liệu lưu trong backend/.data nên vẫn còn sau khi khởi động lại.
const fs = require('fs');
const path = require('path');
const { MongoMemoryServer } = require('mongodb-memory-server');

(async () => {
  const dbPath = path.join(__dirname, '..', '.data');
  fs.mkdirSync(dbPath, { recursive: true });
  const mongod = await MongoMemoryServer.create({
    instance: { port: Number(process.env.MONGO_PORT) || 27018, dbPath, storageEngine: 'wiredTiger' },
  });
  process.env.MONGODB_URI = mongod.getUri('finance_app');
  console.log(`MongoDB nhúng: ${process.env.MONGODB_URI} (dữ liệu: ${dbPath})`);
  const stop = async () => { await mongod.stop(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  require('./server');
})().catch((e) => {
  console.error('Không khởi động được MongoDB nhúng:', e.message);
  process.exit(1);
});
