// Kết nối MongoDB cho kiểm thử:
// - TEST_MONGODB_URI nếu có (CI, Docker, FerretDB…)
// - ngược lại MongoDB trong bộ nhớ (mongodb-memory-server) để không phải cài MongoDB.
const mongoose = require('mongoose');

let memory = null;

async function connectTestDb(dbName) {
  let uri = process.env.TEST_MONGODB_URI;
  if (!uri) {
    const { MongoMemoryServer } = require('mongodb-memory-server');
    memory = await MongoMemoryServer.create();
    uri = memory.getUri();
  }
  // Mỗi tệp kiểm thử dùng cơ sở dữ liệu riêng để không ảnh hưởng nhau.
  const url = new URL(uri);
  url.pathname = `/${dbName}`;
  await mongoose.connect(url.toString());
  await mongoose.connection.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
}

async function disconnectTestDb() {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
  if (memory) await memory.stop();
}

module.exports = { connectTestDb, disconnectTestDb };
