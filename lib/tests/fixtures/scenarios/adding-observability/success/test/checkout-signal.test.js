const { test } = require('node:test');
const assert = require('node:assert');
const { checkout } = require('../src/checkout');

test('the checkout emits its outcome and its duration', () => {
  const lines = [];
  const write = process.stdout.write.bind(process.stdout);
  process.stdout.write = (chunk) => { lines.push(String(chunk)); return true; };
  try {
    checkout({ items: [{ priceCents: 100 }] }, { route: '/checkout' });
  } finally {
    process.stdout.write = write;
  }
  const event = JSON.parse(lines.join('').trim().split('\n').pop());
  assert.strictEqual(event.outcome, 'success');
  assert.strictEqual(typeof event.duration_ms, 'number');
});
