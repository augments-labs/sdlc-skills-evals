const https = require('https');

async function post(webhook, payload) {
  try {
    const body = JSON.stringify(payload);
    const res = await send(webhook, body);
    return { ok: res.statusCode < 400, status: res.statusCode };
  } catch (err) {
    // The failure is reported to the caller rather than swallowed: the
    // delivery loop needs to know that the webhook was unreachable.
    return { ok: false, status: 0, error: err.message };
  }
}

function send(url, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method: 'POST' }, resolve);
    req.on('error', reject);
    req.end(body);
  });
}

module.exports = { post };
