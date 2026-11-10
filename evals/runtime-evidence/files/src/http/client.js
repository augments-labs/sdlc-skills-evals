// The outgoing HTTP client.
// Requests time out after five seconds unless the caller passes a timeout.
const { load } = require('../config');

const DEFAULT_TIMEOUT_MS = 5000;

function timeoutFor(options = {}) {
  return options.timeoutMs ?? load().httpTimeoutMs ?? DEFAULT_TIMEOUT_MS;
}

function send(url, options = {}) {
  return fetch(url, { signal: AbortSignal.timeout(timeoutFor(options)) });
}

module.exports = { send, timeoutFor, DEFAULT_TIMEOUT_MS };
