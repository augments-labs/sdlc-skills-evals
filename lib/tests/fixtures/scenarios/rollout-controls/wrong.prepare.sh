# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong change: the switch guards the request path only. The
# background consumer keeps rendering the new format in both states, so the
# off cohort's work still happens.
cat > "src/consumer.js" <<'INNER'
// The receipt worker renders the invoice too.
function receiptFor(order) {
  return { order: order.id, pdf: 'v2' };
}

module.exports = { receiptFor };
INNER
