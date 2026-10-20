const { flag } = require('./flags');

// The new PDF format is rendered inline by the request handler, behind the
// flag. The switch is read before the render, so turning it off restores the
// prior behaviour with no deploy.
function invoiceResponse(order) {
  if (flag('newInvoicePdf')) return { status: 200, body: { pdf: 'v2' } };
  return { status: 200, body: { pdf: 'v1' } };
}

module.exports = { invoiceResponse };
