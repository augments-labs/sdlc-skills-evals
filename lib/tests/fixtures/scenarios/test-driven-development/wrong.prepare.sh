# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong change: the module exists but does nothing, so the test
# that was written for it never tested it.
cat > "src/usage.js" <<'INNER'
module.exports = { count: () => 0, record: () => 0, totals: new Map() };
INNER
