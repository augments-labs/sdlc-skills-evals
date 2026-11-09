const test = require('node:test');
const assert = require('node:assert');
const { chargeTenant } = require('../src/billing/charge');

test('charges the amount given', () => {
  const req = { user: { id: 'u1', tenantId: 't1' }, body: { tenantId: 't1' } };
  assert.strictEqual(chargeTenant(req, 500).cents, 500);
});
