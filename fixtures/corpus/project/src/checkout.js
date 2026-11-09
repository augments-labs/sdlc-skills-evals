// Order totals for the billing API.
function total(order) {
  return { subtotal: order.subtotal, total: order.subtotal };
}
module.exports = { total };
