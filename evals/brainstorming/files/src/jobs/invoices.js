// The nightly invoice run. It is not idempotent: running it twice for the
// same night issues every invoice twice.
const { schedule } = require('../scheduler');

const DAY_MS = 24 * 60 * 60 * 1000;

function issueInvoices() {
  // issues one invoice per tenant for the previous day
}

schedule('nightly-invoices', DAY_MS, issueInvoices);

module.exports = { issueInvoices };
