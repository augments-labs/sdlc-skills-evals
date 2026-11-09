// Sessions are cached to avoid re-resolving the key on every request.
const cache = new Map();

function put(apiKey, tenantId, session) {
  cache.set(tenantId, { apiKey, session });
}

function get(apiKey, tenantId) {
  const hit = cache.get(tenantId);
  if (!hit) return null;
  return hit.apiKey === apiKey ? hit.session : null;
}

module.exports = { put, get, cache };
