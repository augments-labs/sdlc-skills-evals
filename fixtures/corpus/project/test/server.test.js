const { test } = require('node:test');
const assert = require('node:assert');
const { route, handle } = require('../src/server');
test('unknown route returns 404', async () => {
  assert.strictEqual((await handle({ method: 'GET', path: '/nope' })).status, 404);
});
test('registered route is dispatched', async () => {
  route('GET', '/ping', () => ({ status: 200, body: { ok: true } }));
  assert.deepStrictEqual((await handle({ method: 'GET', path: '/ping' })).body, { ok: true });
});
