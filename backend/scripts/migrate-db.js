// Chép toàn bộ dữ liệu từ MongoDB nhúng (npm run dev:mem, dữ liệu ở backend/.data) sang MongoDB thật
// (MongoDB Atlas hoặc máy chủ riêng) theo MONGODB_URI trong .env.
//
//   npm run db:migrate                     # nguồn mặc định: mongodb://127.0.0.1:27018/finance_app
//   SOURCE_URI=mongodb://... npm run db:migrate
//
// Chạy lại nhiều lần vẫn an toàn: bản ghi được ghi đè theo _id, không tạo bản trùng.
const { MongoClient } = require('mongodb');
const mongoose = require('mongoose');
const config = require('../src/config');
require('../src/models');

const sourceUri = process.env.SOURCE_URI || 'mongodb://127.0.0.1:27018/finance_app';
const mask = (u) => u.replace(/\/\/[^@]*@/, '//***@');
const dbOf = (u) => (u.split('?')[0].match(/^mongodb(?:\+srv)?:\/\/[^/]+\/(.+)$/) || [])[1] || 'finance_app';

async function main() {
  if (sourceUri === config.mongoUri) throw new Error('Nguồn và đích trùng nhau. Đặt MONGODB_URI trong .env thành chuỗi kết nối Atlas.');
  console.log(`Nguồn: ${mask(sourceUri)}`);
  console.log(`Đích:  ${mask(config.mongoUri)} (db: ${config.mongoDb})`);

  const source = new MongoClient(sourceUri, { serverSelectionTimeoutMS: 5000 });
  try {
    await source.connect();
  } catch (e) {
    throw new Error(`Không kết nối được nguồn (${e.message}). Hãy chạy "npm run dev:mem" ở terminal khác rồi chạy lại.`);
  }
  await mongoose.connect(config.mongoUri, { dbName: config.mongoDb, serverSelectionTimeoutMS: 15000 });
  const target = mongoose.connection.db;

  const from = source.db(dbOf(sourceUri));
  const collections = (await from.listCollections({}, { nameOnly: true }).toArray())
    .map((c) => c.name).filter((n) => !n.startsWith('system.'));
  let total = 0;
  for (const name of collections) {
    const docs = await from.collection(name).find().toArray();
    if (docs.length) {
      const ops = docs.map((d) => ({ replaceOne: { filter: { _id: d._id }, replacement: d, upsert: true } }));
      for (let i = 0; i < ops.length; i += 500) await target.collection(name).bulkWrite(ops.slice(i, i + 500), { ordered: false });
    }
    total += docs.length;
    console.log(`  ${name.padEnd(16)} ${docs.length}`);
  }
  // Tạo đủ chỉ mục (duy nhất, TTL…) theo mô hình hiện tại
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  console.log(`Xong: đã chép ${total} bản ghi trong ${collections.length} bảng và tạo chỉ mục.`);
  await source.close();
  await mongoose.disconnect();
}

main().catch(async (e) => {
  console.error('Chuyển dữ liệu thất bại:', e.message);
  await mongoose.disconnect().catch(() => {});
  process.exit(1);
});
