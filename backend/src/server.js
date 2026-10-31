const mongoose = require('mongoose');
const config = require('./config');
const app = require('./app');

async function start() {
  await mongoose.connect(config.mongoUri);
  console.log(`MongoDB đã kết nối: ${config.mongoUri.replace(/\/\/[^@]*@/, '//***@')}`);
  const server = app.listen(config.port, '0.0.0.0', () => console.log(`API đang chạy tại http://0.0.0.0:${config.port}`));
  const stop = () => server.close(() => mongoose.disconnect().then(() => process.exit(0)));
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}
start().catch((e) => {
  console.error('Không khởi động được máy chủ:', e.message);
  process.exit(1);
});
