const mongoose = require('mongoose');
const config = require('./config');
const app = require('./app');

async function start() {
  await mongoose.connect(config.mongoUri, { dbName: config.mongoDb, serverSelectionTimeoutMS: 15000 });
  console.log(`MongoDB đã kết nối: ${config.mongoUri.replace(/\/\/[^@]*@/, '//***@')} (db: ${config.mongoDb})`);
  const server = app.listen(config.port, '0.0.0.0', () => console.log(`API đang chạy tại http://0.0.0.0:${config.port}`));
  const stop = () => server.close(() => mongoose.disconnect().then(() => process.exit(0)));
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}
// Gợi ý cách khắc phục cho các lỗi kết nối MongoDB thường gặp.
function hint(e) {
  const m = `${e.message} ${e.cause?.message || ''}`;
  if (/ECONNREFUSED/.test(m)) return 'Chưa có MongoDB chạy ở địa chỉ này. Kiểm tra MONGODB_URI trong .env, hoặc chạy "npm run dev:mem" để dùng MongoDB nhúng.';
  if (/bad auth|Authentication failed/i.test(m)) return 'Sai tên đăng nhập hoặc mật khẩu database user (Atlas → Database Access). Ký tự đặc biệt trong mật khẩu phải mã hóa URL, ví dụ @ → %40.';
  if (/ENOTFOUND|querySrv/i.test(m)) return 'Không phân giải được tên cluster. Kiểm tra lại chuỗi mongodb+srv://… và kết nối Internet.';
  if (/Server selection timed out|whitelist|not authorized|ReplicaSetNoPrimary/i.test(m)) return 'Atlas từ chối kết nối: thêm IP máy này vào Atlas → Network Access (hoặc 0.0.0.0/0 khi thử nghiệm).';
  return '';
}

start().catch((e) => {
  console.error('Không khởi động được máy chủ:', e.message);
  const h = hint(e);
  if (h) console.error(`Gợi ý: ${h}`);
  process.exit(1);
});
