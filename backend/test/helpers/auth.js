const request = require('supertest');

async function verify(app, registration) {
  const link = registration.body.devLink;
  if (!link) throw new Error(`Không nhận được liên kết xác minh: ${JSON.stringify(registration.body)}`);
  const token = new URL(link).searchParams.get('token');
  const r = await request(app).post('/api/auth/verify-email').send({ token });
  if (r.status !== 200) throw new Error(`Xác minh email thất bại: ${JSON.stringify(r.body)}`);
}
const signup = async (app, name, email, password) => {
  await verify(app, await request(app).post('/api/auth/register').send({ name, email, password }));
  return (await request(app).post('/api/auth/login').send({ email, password })).body;
};
const login = async (app, email, password) =>
  (await request(app).post('/api/auth/login').send({ email, password })).body;

module.exports = { signup, login };
