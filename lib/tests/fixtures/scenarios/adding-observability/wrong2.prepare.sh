# shellcheck shell=bash
# shellcheck disable=SC2154
# The other wrong answer: no test was changed at all. The signal is emitted
# and the alert is there, but nothing holds the signal to its shape.
cat > "test/checkout.test.js" <<'INNER'
const { test } = require('node:test');
const assert = require('node:assert');
const { checkout } = require('../src/checkout');

test('the checkout totals the cart', () => {
  assert.strictEqual(checkout({ items: [{ priceCents: 100 }] }).body.total, 100);
});
INNER
