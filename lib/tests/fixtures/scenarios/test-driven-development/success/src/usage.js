// Per-tenant request counting: one unit per accepted request, and the
// running total for a tenant.
const totals = new Map();

function count(tenantId) {
  return totals.get(tenantId) || 0;
}

function record(tenantId) {
  const next = count(tenantId) + 1;
  totals.set(tenantId, next);
  return next;
}

module.exports = { count, record, totals };
