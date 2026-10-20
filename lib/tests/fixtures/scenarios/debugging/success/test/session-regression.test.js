const { test } = require('node:test');
const assert = require('node:assert');
const { put, get } = require('../src/session');

test('a second key for the same tenant does not evict the first', () => {
  put('k1', 't1', { user: 'a' });
  put('k2', 't1', { user: 'b' });
  assert.deepStrictEqual(get('k1', 't1'), { user: 'a' });
});
