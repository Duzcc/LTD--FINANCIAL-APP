const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { test } = require('node:test');
const assert = require('node:assert/strict');

const configPath = path.join(__dirname, '..', 'src', 'config');

test('Production requires a JWT secret of at least 32 bytes', () => {
  for (const secret of ['', 'short', 'a'.repeat(31)]) {
    const result = spawnSync(process.execPath, ['-e', `require(${JSON.stringify(configPath)})`], {
      env: { ...process.env, NODE_ENV: 'production', JWT_SECRET: secret },
      encoding: 'utf8',
    });
    assert.notEqual(result.status, 0, `accepted a ${secret.length}-byte secret`);
  }

  const result = spawnSync(process.execPath, ['-e', `require(${JSON.stringify(configPath)})`], {
    env: { ...process.env, NODE_ENV: 'production', JWT_SECRET: 'a'.repeat(32) },
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
});
