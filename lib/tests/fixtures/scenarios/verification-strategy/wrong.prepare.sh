# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong battery: the acceptance layer is written, but the
# project's old hollow suite is left in place and the command runs every test
# it finds, so removing the new file alone leaves a green gate and the floor
# is written down, not enforced.
cat > "test/server.test.js" <<'INNER'
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
INNER
cat > "package.json" <<'INNER'
{ "name": "billing-api", "version": "0.3.0", "scripts": { "test": "node --test test/*.test.js" } }
INNER
