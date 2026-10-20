const { bump } = require('./metrics');

const MAX_ATTEMPTS = 5;

async function deliver(webhook, payload, transport) {
  let attempt = 0;
  // The retry loop is bounded: the delivery worker used to retry forever and
  // hammer the customer's endpoint while the webhook was down.
  while (attempt < MAX_ATTEMPTS) {
    attempt++;
    const res = await transport.post(webhook, payload);
    if (res.ok) {
      bump('delivered');
      return { ok: true, attempts: attempt };
    }
    bump('retry');
    // Exponential backoff, so a struggling endpoint is not hammered.
    await new Promise((resolve) => setTimeout(resolve, 100 * Math.pow(2, attempt - 1)));
  }
  bump('exhausted');
  return { ok: false, attempts: attempt };
}

module.exports = { deliver };
