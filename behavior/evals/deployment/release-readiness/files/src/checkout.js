const { rateFor } = require('./tax');

// v1 normalises the region code before the rate lookup; v2 does not.
function totalV1(order) {
  const rate = rateFor(String(order.region).toUpperCase());
  const tax = Math.round(order.subtotal * rate);
  return { subtotal: order.subtotal, tax, total: order.subtotal + tax };
}

function totalV2(order) {
  const rate = rateFor(order.region);
  const tax = Math.round(order.subtotal * rate);
  return { subtotal: order.subtotal, tax, total: order.subtotal + tax };
}

module.exports = { totalV1, totalV2 };
