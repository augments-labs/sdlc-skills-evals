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
work="$(mktemp -d)"
trap 'rm -rf "$standin" "$work"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

# the pin a run resolves when the caller names none
inv_commit="$(jq -r '.upstream.commit' "$here/config/upstream-inventory.json")"

l="selftest-$$"
trap 'rm -rf "$here"/results/*-"$l" "$here"/results/*-"$l"-*' EXIT
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

# --- the pin a campaign freezes ----------------------------------------------
#
# A campaign with no --plugin freezes the committed upstream commit, and
# names the exact invocations it plans.

l3="selftest-pin-$$"
out="$("$here/bin/campaign" new "$l3" --harness fake --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" 2>&1)"
d3="$(ls -d "$here"/results/*-"$l3" 2>/dev/null | head -1)"
if [ -n "$d3" ] && jq -e --arg c "$inv_commit" '.plugin_commit == $c and .plugin_ref == $c' \
    "$d3/campaign.json" >/dev/null 2>&1; then
  ok "a campaign with no --plugin freezes the committed pin"
else
  bad "a campaign with no --plugin freezes the committed pin"
fi
printf '%s' "$out" | grep -qF "pin        : $inv_commit" \
  && ok "the campaign names the pin it froze" || bad "the campaign names the pin it froze"
printf '%s' "$out" | grep -qF "command    : bin/behavior --harness fake --scenario probe-ok --arm green --plugin $inv_commit" \
  && ok "the campaign names the exact planned invocations" \
  || bad "the campaign names the exact planned invocations"
rm -rf "$here"/results/*-"$l3"

# --- a campaign runs the commit it froze, not a tag that moved ---------------
#
# A tag may be named when the campaign is prepared; the commit it names is
# frozen, and the run uses that commit — a tag that moves between the two
# cannot become the pin of the run.

tag_repo="$work/tags"
mkdir -p "$tag_repo"
git -C "$tag_repo" init -q
git -C "$tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
one="$(git -C "$tag_repo" rev-parse HEAD)"
git -C "$tag_repo" tag selftest-campaign-tag
git -C "$tag_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
two="$(git -C "$tag_repo" rev-parse HEAD)"
l4="selftest-tag-$$"
SDLC_SKILLS_ROOT="$tag_repo" "$here/bin/campaign" new "$l4" --plugin selftest-campaign-tag \
  --harness fake --arms green --scenarios probe-ok --runs 1 \
  --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
d4="$(ls -d "$here"/results/*-"$l4" 2>/dev/null | head -1)"
if [ -n "$d4" ] && jq -e --arg c "$one" '.plugin_commit == $c' "$d4/campaign.json" >/dev/null 2>&1; then
  ok "the campaign froze the commit the tag named"
else
  bad "the campaign froze the commit the tag named"
fi
git -C "$tag_repo" tag -f selftest-campaign-tag "$two" >/dev/null 2>&1
SDLC_SKILLS_ROOT="$tag_repo" "$here/bin/campaign" run "$l4" >/dev/null 2>&1
if [ -n "$d4" ] && jq -e --arg c "$one" '.plugin_commit == $c' \
    "$d4/runs/probe-ok-green-1.json" >/dev/null 2>&1; then
  ok "the run used the frozen commit, not the moved tag"
else
  bad "the run used the frozen commit, not the moved tag"
fi
rm -rf "$here"/results/*-"$l4"

# --- the non-launching paths -------------------------------------------------
#
# A sentinel real CLI stands on PATH: it fails and records that it was
# called. The help and the campaign preparation must never reach it.

sentinel_log="$work/sentinel.log"
sentinel_dir="$work/sentinel"
mkdir -p "$sentinel_dir"
for cli in opencode claude codex kimi; do
  cat >"$sentinel_dir/$cli" <<SENTINEL
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$sentinel_log"
exit 1
SENTINEL
  chmod +x "$sentinel_dir/$cli"
done
PATH="$sentinel_dir:$PATH"; export PATH

l5="selftest-sentinel-$$"
"$here/bin/campaign" --help >/dev/null 2>&1
"$here/bin/campaign" new "$l5" --harness opencode --plugin "$standin" --arms green \
  --scenarios probe-ok --runs 1 --scenario-dir "$here/lib/tests/fake-cli/scenarios" >/dev/null 2>&1
[ ! -f "$sentinel_log" ] && ok "help and the campaign preparation call no CLI" \
  || bad "help and the campaign preparation call no CLI (the sentinel was called)"

# the control: the campaign RUN does reach the CLI, so the case above is
# not vacuous. The sentinel fails, so nothing is spent.
"$here/bin/campaign" run "$l5" >/dev/null 2>&1
[ -f "$sentinel_log" ] && ok "the campaign run reaches the CLI (the control)" \
  || bad "the campaign run reaches the CLI (the control)"
rm -rf "$here"/results/*-"$l5"

exit "$fails"
