// Added by the pull request under review.
const { rateFor } = require('./tax');

function invoice(order) {
  const rate = rateFor(order.region);
  return { id: order.id, total: order.subtotal + Math.round(order.subtotal * rate) };
}

module.exports = { invoice };
