#!/usr/bin/env bash
# Offline test: bin/triggering via the fake harness only. The fake emits a
# fixed SKILL line (FAKE_SUBJECT) or none (FAKE_FIRE=0), so the scoring
# loop's reductions are exercised with zero live calls. No token spent.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
export SDLC_SKILLS_EVALS_ROOT="$here"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
trap 'rm -rf "$standin"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed

base=(--harness fake --harness-dir "$fake_h" --plugin "$standin")

# --dry-run prices without pinning or calling anything (no --plugin needed)
out="$("$here/bin/triggering" --harness fake --skill yagni --dry-run 2>&1)"
[ "$?" -eq 0 ] && printf '%s' "$out" | grep -qE "[0-9]+ (calls|invocations)" \
  && ok "dry-run prices without calling" || bad "dry-run prices without calling"

# firing fake: positives pass, negatives fail, sheet exits 1
out="$(FAKE_FIRE=1 FAKE_SUBJECT=yagni "$here/bin/triggering" "${base[@]}" \
  --skill yagni --split train --runs 1 --jobs 2 2>&1)"
rc="$?"
[ "$rc" -eq 1 ] && ok "mixed sheet exits 1" || bad "mixed sheet exits 1 (got $rc)"
printf '%s' "$out" | grep -q "PASS" && ok "positives pass" || bad "positives pass"
printf '%s' "$out" | grep -q "should have routed to" \
  && ok "negative failures name the route" || bad "negative failures name the route"

# silent fake: positives miss with the observed-routing diagnostic
out="$(FAKE_FIRE=0 "$here/bin/triggering" "${base[@]}" \
  --skill yagni --split train --runs 1 --jobs 2 2>&1)"
printf '%s' "$out" | grep -q "expected yagni to fire | observed: (nothing routed)" \
  && ok "misses name the observation" || bad "misses name the observation"

# an empty split scores nothing and passes
out="$("$here/bin/triggering" "${base[@]}" --skill yagni --split holdout --runs 1 2>&1)"
[ "$?" -eq 0 ] && printf '%s' "$out" | grep -q "no queries in this split" \
  && ok "empty split is quiet" || bad "empty split is quiet"

# an unrunnable harness measures nothing, via exit 2 before any launch
out="$("$here/bin/triggering" --harness codex --skill yagni --dry-run 2>&1)"
[ "$?" -eq 0 ] || bad "dry-run ignores harness runnable state"
"$here/bin/triggering" --harness codex --skill yagni --plugin "$standin" --runs 1 >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "unrunnable harness exits 2" || bad "unrunnable harness exits 2"

exit "$fails"
