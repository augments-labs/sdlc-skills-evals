# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong fix: the symptom goes away in the wrong file. The cache
# is still keyed by tenant, so a second key evicts the first — and the
# regression test the run left behind goes red.
cat > "src/session.js" <<'INNER'
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
INNER
