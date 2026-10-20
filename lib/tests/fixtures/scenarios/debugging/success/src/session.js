// Sessions are cached to avoid re-resolving the key on every request. The
// cache is keyed by the API key itself, so a second key for one tenant
// cannot evict the first.
const cache = new Map();

function put(apiKey, tenantId, session) {
  cache.set(apiKey, { tenantId, session });
}

function get(apiKey, tenantId) {
  const hit = cache.get(apiKey);
  if (!hit) return null;
  return hit.session;
}

module.exports = { put, get, cache };
