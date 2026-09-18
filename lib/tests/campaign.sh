#!/usr/bin/env bash
# Offline test: bin/campaign via the fake harness only (the `fake` name
# routes to lib/tests/fake-cli for self-tests). Nothing here launches a
# live CLI. No token spent.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
export SDLC_SKILLS_EVALS_ROOT="$here"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
trap 'rm -rf "$standin"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

l="selftest-$$"
trap 'rm -rf "$here"/results/*-"$l"' EXIT
"$here/bin/campaign" new "$l" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1 \
  || { bad "campaign new"; exit "$fails"; }
d="$(ls -d "$here"/results/*-"$l")"
jq -e --arg c "$plug_commit" '.plugin_commit == $c and .harness == "fake" and (.arms | type == "array")' \
  "$d/campaign.json" >/dev/null && ok "inputs frozen with the key set" || bad "inputs frozen with the key set"

"$here/bin/campaign" report "$l" >/dev/null 2>&1 \
  && bad "report refused before runs end" || ok "report refused before runs end"

"$here/bin/campaign" run "$l" >/dev/null 2>&1 \
  || { bad "campaign run"; exit "$fails"; }
"$here/bin/campaign" report "$l" >/dev/null 2>&1 \
  || { bad "campaign report"; exit "$fails"; }
grep -q "^## Commit" "$d/summary.md" && ok "summary has Commit" || bad "summary has Commit"
grep -q "^## Behavior scenarios" "$d/summary.md" && ok "summary has Behavior scenarios" || bad "summary has Behavior scenarios"
grep -q "^## Costs" "$d/summary.md" && ok "summary has Costs" || bad "summary has Costs"
grep -q "probe-ok" "$d/summary.md" && ok "summary names the scenario" || bad "summary names the scenario"

# a manifest-less probe scenario cannot go green, even in a campaign
l2="selftest-nochecks-$$"
"$here/bin/campaign" new "$l2" --plugin "$standin" --harness fake --arms green \
  --scenarios probe-nochecks --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d2="$(ls -d "$here"/results/*-"$l2")"
"$here/bin/campaign" run "$l2" >/dev/null 2>&1
jq -e '.verdict == "indeterminate" and .stage == "checks"' "$d2/runs/probe-nochecks-green-1.json" >/dev/null \
  && ok "campaign records indeterminate, never false green" || bad "campaign records indeterminate, never false green"
rm -rf "$here"/results/*-"$l2"

exit "$fails"
