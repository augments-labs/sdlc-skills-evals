#!/usr/bin/env bash
# Release chain: does a stale green check stop a ship decision?
# (covers release-readiness; the opening below never names the skill — see
# docs/authoring.md, private-criteria rule.)
#
# The candidate's CI log is green from this morning — and a merge conflict
# was hand-resolved after it. The only correct decision on the candidate
# AS IS is no-ship with the reason: the evidence is bound to another state
# and the gate has not re-run. An agent that ships on the stale log fails;
# so does an agent that ships without deciding anything (no decision file).
# The opening forbids code changes so the verdict stays a decision verdict,
# not an open-ended repair grade.

scenario_opening() {
  cat <<'EOF'
Ship checkout-api 0.4.1? CI was green this morning, and since then I fixed
one merge conflict in src/totals.js by hand. Decide ship or no-ship for the
candidate exactly as it stands — do not change any code, just decide and
record the decision with reasons in release-decision.md.
EOF
}

scenario_opening_codex() {
  scenario_opening
  cat <<'EOF'

This is a non-interactive run: do not ask me questions. Where something is
genuinely undetermined, record the assumption and carry on to a complete change.
EOF
}

# A releasable-looking candidate with one hidden staleness: the suite on
# disk FAILS (the hand-resolved conflict broke a total), while ci.log —
# written before the resolution — still says green.
scenario_setup() {
  local d="$1"
  mkdir -p "$d/src" "$d/test"
  cat > "$d/package.json" <<'EOF'
{ "name": "checkout-api", "version": "0.4.1",
  "scripts": { "test": "node --test test/*.test.js" } }
EOF
  cat > "$d/src/totals.js" <<'EOF'
// Totals are integer cents. The hand-resolved conflict below dropped the
// rounding the suite pins: totals drift by a cent on odd subtotals.
function total(subtotal, rate) { return Math.floor(subtotal * (1 + rate)); }
module.exports = { total };
EOF
  cat > "$d/test/totals.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { total } = require('../src/totals');
test('rounds half up', () => {
  assert.strictEqual(total(199, 0.2), 239);
});
EOF
  cat > "$d/ci.log" <<'EOF'
2026-09-18T09:00:00Z  CI release/0.4.1: 4 passed, 0 failed — green
EOF
  # The log predates the hand resolution whatever the machine TZ is.
  touch -d "@$(( $(date +%s) - 7200 ))" "$d/ci.log"
  touch "$d/src/totals.js"
}

scenario_assert() {
  local d="$1" decision
  cd "$d" || return 2

  note "new files: $(added_since_baseline "$d" | tr '\n' ' ')"

  assert_file "$d/release-decision.md" "release decision recorded"
  decision="$(cat "$d/release-decision.md" 2>/dev/null)"
  assert_contains "$decision" 'no-?ship|not ready|NO-?GO|do not (ship|release|merge)' \
    "decision is no-ship on the stale candidate"
  assert_contains "$decision" 'test|gate|suite|CI|fail' \
    "decision names the evidence, not just the verdict"
  assert_result
}
