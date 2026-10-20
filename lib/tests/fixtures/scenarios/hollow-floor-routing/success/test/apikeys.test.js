const { test } = require('node:test');
const assert = require('node:assert');
const { register, resolve } = require('../src/apikeys');

test('a registered key resolves to its record', () => {
  register('k1', 't1', 'pro');
  assert.deepStrictEqual(resolve('Bearer k1'), { tenantId: 't1', tier: 'pro' });
});
