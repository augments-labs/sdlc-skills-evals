// The gateway takes amounts in minor units and rejects anything that is not a
// whole number.
function charge(order, amount) {
  if (!Number.isInteger(amount)) {
    return { status: 402, body: { error: 'payment_declined' } };
  }
  return { status: 200, body: { charged: amount, order: order.id } };
}
module.exports = { charge };
