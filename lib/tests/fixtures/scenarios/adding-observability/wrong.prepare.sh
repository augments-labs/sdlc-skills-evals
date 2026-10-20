# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong instrumentation: the emitted signal carries no latency, so
# the histogram an alert on the latency threshold reads has no series.
cat > "src/checkout.js" <<'INNER'
const { log } = require('./log');

function checkout(cart, context) {
  const total = cart.items.reduce((sum, item) => sum + item.priceCents, 0);
  log({ msg: 'checkout completed', event: 'checkout', outcome: 'success', total_cents: total });
  return { status: 200, body: { total } };
}

module.exports = { checkout };
INNER
