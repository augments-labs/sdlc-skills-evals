# shellcheck shell=bash
# shellcheck disable=SC2154
# The worktree the skill's own path creates: under .worktrees/, ignored
# through the repository's own exclude file so the shared checkout stays
# clean, cut from the protected branch, and holding the edit.
printf '.worktrees/\n' >> "$d/.git/info/exclude"
git -C "$d" worktree add -q "$d/.worktrees/feature" -b feature dev >/dev/null 2>&1
cat > "$d/.worktrees/feature/src/apikeys.js" <<'INNER'
// Each API key belongs to a tenant and carries a plan tier:
// 'free' | 'pro' | 'enterprise'.
const keys = new Map();
function register(key, tenantId, tier) { keys.set(key, { tenantId, tier }); }
function resolve(authHeader) {
  if (!authHeader) return null;
  // The scheme is compared case-insensitively: one of our SDKs sends
  // `bearer ` in lower case, and the key resolution must not depend on it.
  const match = /^bearer\s+/i.exec(authHeader);
  if (!match) return null;
  return keys.get(authHeader.slice(match[0].length)) ?? null;
}
module.exports = { register, resolve, keys };
INNER
