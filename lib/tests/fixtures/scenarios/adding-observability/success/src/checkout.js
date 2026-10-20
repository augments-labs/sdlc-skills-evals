const { log } = require('./log');

// The checkout's outcome and how long it took are emitted on every call, so
// the success rate an alert reads has a series while things are fine.
function checkout(cart, context) {
  const started = process.hrtime.bigint();
  const total = cart.items.reduce((sum, item) => sum + item.priceCents, 0);
  const durationMs = Number(process.hrtime.bigint() - started) / 1e6;
  log({
    msg: 'checkout completed',
    event: 'checkout',
    outcome: 'success',
    route: context && context.route ? context.route : '/checkout',
    duration_ms: durationMs,
    total_cents: total,
  });
  return { status: 200, body: { total } };
}

module.exports = { checkout };
