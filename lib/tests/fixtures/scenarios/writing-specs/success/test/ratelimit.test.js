const { test } = require('node:test');
const assert = require('node:assert');
const { allowanceFor, enforce } = require('../src/ratelimit');

test('the free tier has a thousand requests of budget a month', () => {
  assert.strictEqual(allowanceFor('free'), 1000);
});

test('the pro tier has fifty thousand requests of budget a month', () => {
  assert.strictEqual(allowanceFor('pro'), 50000);
});

test('the enterprise tier is unlimited', () => {
  assert.strictEqual(allowanceFor('enterprise'), Infinity);
});

test('a request over the ceiling is refused with a retry hint', () => {
  const response = enforce('free', 1001);
  assert.strictEqual(response.status, 429);
  assert.ok(response.headers['retry-after']);
});
