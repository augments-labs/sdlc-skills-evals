// The per-key allowance, not built yet: the ceilings are not wired to the
// request path, so the criterion in test/ratelimit.test.js fails.
function allowanceFor(plan) {
  return 0;
}

function enforce(plan, used) {
  return { status: 200, body: { allowed: true } };
}

module.exports = { allowanceFor, enforce };
