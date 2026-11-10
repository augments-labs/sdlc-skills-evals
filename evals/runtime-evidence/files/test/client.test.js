const test = require('node:test');
const assert = require('node:assert');
const { timeoutFor } = require('../src/http/client');

test('uses the request timeout', () => {
  assert.strictEqual(timeoutFor({ timeoutMs: 200 }), 200);
});
