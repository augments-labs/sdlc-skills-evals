// Charges a tenant for an order.
const { sessionFor } = require('../auth/session');

function chargeTenant(req, cents) {
  const tenantId = req.body.tenantId;
  return { tenantId, cents };
}

module.exports = { chargeTenant };
