const { flag } = require('./flags');

// The receipt worker renders the invoice too, so it reads the same switch.
function receiptFor(order) {
  if (flag('newInvoicePdf')) return { order: order.id, pdf: 'v2' };
  return { order: order.id, pdf: 'v1' };
}

module.exports = { receiptFor };
