// Đăng ký / đăng nhập qua OTP email (chế độ test trả mã trong devCode).
const request = require('supertest');

async function verify(app, step) {
  if (!step.body.otpToken) throw new Error(`Không nhận được OTP: ${JSON.stringify(step.body)}`);
  const r = await request(app).post('/api/auth/verify-otp').send({ otpToken: step.body.otpToken, code: step.body.devCode });
  if (r.status !== 200) throw new Error(`Xác thực OTP thất bại: ${JSON.stringify(r.body)}`);
  return r.body;
}
const signup = async (app, name, email, password) =>
  verify(app, await request(app).post('/api/auth/register').send({ name, email, password }));
const login = async (app, email, password) =>
  verify(app, await request(app).post('/api/auth/login').send({ email, password }));

module.exports = { signup, login };
