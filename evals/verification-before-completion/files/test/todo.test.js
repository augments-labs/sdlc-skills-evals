const { test } = require('node:test');
const assert = require('node:assert');
const { add, list, toggle } = require('../src/todo');

test('adds an item', () => {
  add('buy milk');
  assert.ok(list().some((i) => i.text === 'buy milk'));
});

test('toggling twice restores the state', () => {
  add('buy eggs');
  toggle(1);
  assert.strictEqual(toggle(1).done, false);
});
