const { test } = require('node:test');
const assert = require('node:assert');
const { count, record } = require('../src/usage');

test('the running total for a tenant counts one unit per request', () => {
  record('t1');
  record('t1');
  assert.strictEqual(count('t1'), 2);
});
