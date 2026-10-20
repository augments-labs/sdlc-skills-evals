const { test } = require('node:test');
const assert = require('node:assert');
const { route, handle } = require('../src/server');
const { register, resolve } = require('../src/apikeys');

test('an unknown route returns 404', async () => {
  assert.strictEqual((await handle({ method: 'GET', path: '/nope' })).status, 404);
});

test('a registered route is dispatched', async () => {
  route('GET', '/ping', () => ({ status: 200, body: { ok: true } }));
  assert.deepStrictEqual((await handle({ method: 'GET', path: '/ping' })).body, { ok: true });
});

test('a registered API key resolves to its record', () => {
  register('k1', 't1', 'pro');
  assert.deepStrictEqual(resolve('Bearer k1'), { tenantId: 't1', tier: 'pro' });
});
