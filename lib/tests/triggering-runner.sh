#!/usr/bin/env bash
# Offline test: bin/triggering — its scoring loop, the plans it prints,
# and the offline paths that must launch nothing.
#
# The fake emits a fixed SKILL line (FAKE_SUBJECT) or none (FAKE_FIRE=0),
# so the loop's reductions are exercised with zero live calls. Almost
# every run here uses the FAKE adapter (--harness fake with --harness-dir
# lib/tests/fake-cli). The exceptions, and what each of them reaches:
#
#   the case that names --harness codex reads that adapter's header and
#     is refused before any launch, because the adapter is unrunnable.
#   the live-path control sources the real opencode adapter and reaches
#     the SENTINEL CLI on PATH — one that fails and records the call —
#     so the case above is not vacuous. The sentinel spends nothing.
#
# No case in this file reaches a real agent CLI: the sentinel stands in
# for one, and it always fails.
set -uo pipefail
# git reads no user or system configuration here: one that converts files
# (core.autocrlf=true, for example) would change what these cases check out.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
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

# --- the pin a run resolves --------------------------------------------------
#
# The default plugin is the committed upstream commit: a commit, never a
# moving branch. The dry run names it, and names the exact command a live
# run would be, without pinning, calling or launching anything.

out="$("$here/bin/triggering" --harness fake --skill yagni --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "the dry run names the pinned commit" || bad "the dry run names the pinned commit"

# the plan is the whole command, option by option: a prefix match would
# let a plan that drops an option pass
plan_cmd() { # $1 output — the printed command line and nothing else
  printf '%s\n' "$1" | sed -n 's/^command  : //p'
}
out="$("$here/bin/triggering" --harness fake --harness-dir "$fake_h" --skill yagni \
  --runs 2 --jobs 1 --split train --timeout 30 --max-turns 4 --json "$work/out.json" \
  --no-fixture --dry-run 2>&1)"
want="bin/triggering --harness fake --skill yagni --plugin $inv_commit --runs 2 --jobs 1 --split train --timeout 30 --max-turns 4 --json $work/out.json --no-fixture --harness-dir $fake_h"
if [ "$(plan_cmd "$out")" = "$want" ]; then
  ok "the dry run names the whole planned invocation"
else
  bad "the dry run names the whole planned invocation (got '$(plan_cmd "$out")')"
fi

# the --all branch names every option the live path honours: the
# expectation is the whole option set, not the subset this call passes
all_desc="$work/desc-all"
mkdir -p "$all_desc"
printf '%s\n' '[{"query":"probe","should_trigger":true,"split":"train","expect":"probe"}]' \
  >"$all_desc/probe.json"
out="$(DESCRIPTIONS_ROOT="$all_desc" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --all --runs 2 --jobs 1 --split train --timeout 30 --max-turns 4 \
  --json "$work/out-all.json" --no-fixture --dry-run 2>&1)"
want="bin/triggering --harness fake --all --plugin $inv_commit --runs 2 --jobs 1 --split train --timeout 30 --max-turns 4 --json $work/out-all.json --no-fixture --harness-dir $fake_h"
if [ "$(plan_cmd "$out")" = "$want" ]; then
  ok "the --all plan names the whole planned invocation"
else
  bad "the --all plan names the whole planned invocation (got '$(plan_cmd "$out")')"
fi

# an explicit plugin is named as it was given
out="$("$here/bin/triggering" --harness fake --skill yagni --plugin "$standin" --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "command  : bin/triggering --harness fake --skill yagni --plugin $standin" \
  && ok "the dry run names the plugin the caller gave" \
  || bad "the dry run names the plugin the caller gave"

# a run that cannot resolve the default pin says so instead of running
# something else
out="$(SDLC_SKILLS_ROOT="$standin" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill yagni --runs 1 --split train 2>&1)"
rc="$?"
[ "$rc" -eq 2 ] && ok "a run that cannot resolve the default pin refuses" \
  || bad "a run that cannot resolve the default pin refuses (exit $rc)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "the refusal names the pinned commit" || bad "the refusal names the pinned commit"

# an inventory that names no commit is refused, and NO tree is named in
# its place: the runner falls back to nothing, never to some other tree
broken_inv="$work/no-commit-inventory.json"
jq '.upstream.commit = "v11.0.0"' "$here/config/upstream-inventory.json" > "$broken_inv"
out="$(INVENTORY_PATH="$broken_inv" "$here/bin/triggering" --harness fake --skill yagni \
  --dry-run 2>&1)"
rc="$?"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "no usable upstream pin"; then
  ok "the descriptions runner refuses a default pin it cannot resolve"
else
  bad "the descriptions runner refuses a default pin it cannot resolve (exit $rc, got '$out')"
fi
case "$out" in
  *"plugin   :"*) bad "the refusal names no tree in place of the pin";;
  *) ok "the refusal names no tree in place of the pin";;
esac

# a one-query set, so a live run costs one observation and not a whole
# sheet
desc_work="$work/descriptions"
mkdir -p "$desc_work"
printf '%s\n' '[{"query":"probe","should_trigger":true,"split":"train","expect":"probe"}]' \
  >"$desc_work/probe.json"

# a run pinned by commit uses a pinned tree, not the moving checkout
printf 'pinned\n' >"$standin/pinned-marker.txt"
git -C "$standin" add -A
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q -m marker
plug_commit="$(git -C "$standin" rev-parse HEAD)"
launch_log="$work/launch.log"
out="$(SDLC_SKILLS_ROOT="$standin" FAKE_LAUNCH_LOG="$launch_log" \
  DESCRIPTIONS_ROOT="$work/descriptions" \
  "$here/bin/triggering" --harness fake --harness-dir "$fake_h" --skill probe \
  --plugin "$plug_commit" --runs 1 --split train 2>&1)"
printf '%s' "$out" | grep -qF "$plug_commit" \
  && ok "a live run names the pin it resolved" || bad "a live run names the pin it resolved"
install_path="$(sed -n 's/^install //p' "$launch_log" 2>/dev/null | head -1)"
if [ -n "$install_path" ] && [ "$install_path" != "$standin" ]; then
  ok "a run pinned by commit does not use the moving checkout"
else
  bad "a run pinned by commit does not use the moving checkout (installed '$install_path')"
fi

# --- what a run installs -----------------------------------------------------
#
# A directory plugin is the operator's own working tree and is used as it
# is, so the runner names THAT TREE — not a commit it would describe
# content the run never measured. A ref is pinned into a worktree, so the
# tree is the commit it names.

plugdir="$work/plugdir"
mkdir -p "$plugdir"
git -C "$plugdir" init -q
git -C "$plugdir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tree
out="$("$here/bin/triggering" --harness fake --harness-dir "$fake_h" --plugin "$plugdir" --skill yagni --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "plugin   : $plugdir" \
  && ok "the dry run names the tree a directory plugin installs" \
  || bad "the dry run names the tree a directory plugin installs"
launch_log2="$work/launch2.log"
out="$(SDLC_SKILLS_ROOT="$standin" FAKE_LAUNCH_LOG="$launch_log2" \
  DESCRIPTIONS_ROOT="$work/descriptions" \
  "$here/bin/triggering" --harness fake --harness-dir "$fake_h" --skill probe \
  --plugin "$plugdir" --runs 1 --split train 2>&1)"
printf '%s' "$out" | grep -qF "plugin   : $plugdir" \
  && ok "a live run names the tree it installs" || bad "a live run names the tree it installs"
if grep -q "^install $plugdir\$" "$launch_log2" 2>/dev/null; then
  ok "a directory plugin installs the tree it names"
else
  bad "a directory plugin installs the tree it names"
fi

# the dry run names every option the live path honours
out="$("$here/bin/triggering" --harness fake --harness-dir "$fake_h" --skill yagni --dry-run 2>&1)"
printf '%s' "$out" | grep -qF -- "--harness-dir $fake_h" \
  && ok "the dry run names the harness directory" || bad "the dry run names the harness directory"

# --- a ref plugin: the plan names a commit, and the plan installs it --------
#
# A ref moves. The plan resolves it once and its command carries the
# commit it named, so a tag that moves afterwards cannot change what the
# plan installs.

tagrepo="$work/tags"
mkdir -p "$tagrepo"
git -C "$tagrepo" init -q
git -C "$tagrepo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
tag_one="$(git -C "$tagrepo" rev-parse HEAD)"
git -C "$tagrepo" tag selftest-plan-tag
git -C "$tagrepo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
tag_two="$(git -C "$tagrepo" rev-parse HEAD)"
out="$(SDLC_SKILLS_ROOT="$tagrepo" DESCRIPTIONS_ROOT="$work/descriptions" "$here/bin/triggering" \
  --harness fake --harness-dir "$fake_h" --skill probe --plugin selftest-plan-tag \
  --runs 1 --split train --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "plugin   : $tag_one" \
  && ok "the dry run names the commit a ref resolves to" \
  || bad "the dry run names the commit a ref resolves to"
plan="$(plan_cmd "$out")"
case "$plan" in
  *"--plugin $tag_one"*) ok "the planned command carries the commit, not the ref";;
  *) bad "the planned command carries the commit, not the ref (got '$plan')";;
esac
# the tag moves: the plan's command still installs the commit it named
git -C "$tagrepo" tag -f selftest-plan-tag "$tag_two" >/dev/null 2>&1
out2="$( cd "$here" && SDLC_SKILLS_ROOT="$tagrepo" DESCRIPTIONS_ROOT="$work/descriptions" \
  eval "$plan" 2>&1 )"
printf '%s' "$out2" | grep -qF "plugin   : $tag_one" \
  && ok "the planned command still installs the commit the plan froze" \
  || bad "the planned command still installs the commit the plan froze (got '$(printf '%s' "$out2" | sed -n 's/^plugin   : //p')')"

# --- flat sets, and the holdout kept apart ----------------------------------
#
# A set is <root>/<skill>.json; its holdout is <root>/holdout/<skill>.json,
# written after selection. The main splits read the set alone and the
# holdout split reads the holdout alone, under --skill and --all both: a
# holdout read during selection is no longer untouched. A set nested one
# level down is not a set at all.

iso="$work/desc-iso"
mkdir -p "$iso/holdout" "$iso/legacy"
printf '%s\n' '[{"query":"main train q","should_trigger":true,"split":"train"},
 {"query":"main validation q","should_trigger":false,"split":"validation"}]' >"$iso/probe.json"
printf '%s\n' '[{"query":"holdout q","should_trigger":true,"split":"holdout"}]' >"$iso/holdout/probe.json"
printf '%s\n' '[{"query":"nested legacy q","should_trigger":true,"split":"train"}]' >"$iso/legacy/other.json"

queries_of() { # $1 json results — the sorted queries it scored, one per line
  jq -r '.[].query' "$1" 2>/dev/null | sort | paste -sd'|' -
}
iso_run() { # $1 out json, rest: selection args
  local out="$1"; shift
  DESCRIPTIONS_ROOT="$iso" FAKE_FIRE=1 FAKE_SUBJECT=probe "$here/bin/triggering" \
    "${base[@]}" "$@" --runs 1 --jobs 1 --json "$out" >/dev/null 2>&1
}

iso_run "$work/iso-skill-all.json" --skill probe --split all
got="$(queries_of "$work/iso-skill-all.json")"
[ "$got" = "main train q|main validation q" ] \
  && ok "--skill --split all reads the flat set and not its holdout" \
  || bad "--skill --split all reads the flat set and not its holdout (scored '$got')"

iso_run "$work/iso-skill-train.json" --skill probe --split train
got="$(queries_of "$work/iso-skill-train.json")"
[ "$got" = "main train q" ] \
  && ok "--skill --split train reads the set's train split alone" \
  || bad "--skill --split train reads the set's train split alone (scored '$got')"

iso_run "$work/iso-skill-holdout.json" --skill probe --split holdout
got="$(queries_of "$work/iso-skill-holdout.json")"
[ "$got" = "holdout q" ] \
  && ok "--skill --split holdout reads the holdout alone" \
  || bad "--skill --split holdout reads the holdout alone (scored '$got')"

iso_run "$work/iso-all-all.json" --all --split all
got="$(queries_of "$work/iso-all-all.json")"
[ "$got" = "main train q|main validation q" ] \
  && ok "--all --split all reads depth-1 sets, no holdout, no nested set" \
  || bad "--all --split all reads depth-1 sets, no holdout, no nested set (scored '$got')"

iso_run "$work/iso-all-holdout.json" --all --split holdout
got="$(queries_of "$work/iso-all-holdout.json")"
[ "$got" = "holdout q" ] \
  && ok "--all --split holdout reads the holdouts alone" \
  || bad "--all --split holdout reads the holdouts alone (scored '$got')"

# a set that only exists nested is not found under --skill
DESCRIPTIONS_ROOT="$iso" "$here/bin/triggering" "${base[@]}" --skill other \
  --split train --runs 1 >/dev/null 2>&1
rc="$?"
[ "$rc" -eq 2 ] && ok "a nested set is not a set (--skill exits 2)" \
  || bad "a nested set is not a set (--skill exits 2, got $rc)"

# the dry run prices the same queries the run would score
out="$(DESCRIPTIONS_ROOT="$iso" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill probe --split all --runs 3 --dry-run 2>&1)"
printf '%s' "$out" | grep -qE '(^|[^0-9])6 (calls|invocations)' \
  && ok "the dry run prices the flat set alone (2 queries x 3 runs)" \
  || bad "the dry run prices the flat set alone (2 queries x 3 runs; got '$(printf '%s' "$out" | grep -E 'calls|invocations')')"

# the selection loop is the lab's to run now: the build-only ban is gone
help_text="$("$here/bin/triggering" --help 2>&1)"
case "$help_text" in
  *"no selection run ever starts from here"*|*BUILD-ONLY*)
    bad "the help carries no build-only ban";;
  *) ok "the help carries no build-only ban";;
esac
if grep -qE 'no selection run ever starts from here|BUILD-ONLY' "$here/bin/triggering"; then
  bad "the header carries no build-only ban"
else
  ok "the header carries no build-only ban"
fi

# --- a summary for the record ------------------------------------------------
#
# --summary PATH writes one JSON object beside the per-query records: which
# skill text and which description the run scored, the per-split counts, and
# one row per query. bin/report copies it into a record. It carries no
# transcript, stream, or observed routing.

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
sumrepo="$work/sumrepo"
mkdir -p "$sumrepo/skills/common/probe"
printf -- '---\nname: probe\ndescription: "probe one"\n---\n\nbody\n' > "$sumrepo/skills/common/probe/SKILL.md"
git -C "$sumrepo" init -q
git -C "$sumrepo" add -A
git -C "$sumrepo" -c user.name=t -c user.email=t@example.invalid commit -q -m probe
sum_commit="$(git -C "$sumrepo" rev-parse HEAD)"
sum_tree="$(git -C "$sumrepo" rev-parse HEAD:skills/common/probe)"
sumdesc="$work/sumdesc"
mkdir -p "$sumdesc/holdout"
printf '%s\n' '[{"query":"fire a","should_trigger":true,"split":"train"},
 {"query":"quiet b","should_trigger":false,"split":"train"},
 {"query":"fire c","should_trigger":true,"split":"validation"},
 {"query":"quiet d","should_trigger":false,"split":"validation"},
 {"query":"fire wrongly e","should_trigger":false,"split":"validation"},
 {"query":"refused f","should_trigger":true,"split":"validation"}]' > "$sumdesc/probe.json"
printf '%s\n' '[{"query":"fire h","should_trigger":true,"split":"holdout"}]' > "$sumdesc/holdout/probe.json"
# the session: names its model, fires probe on a "fire" query, and is
# refused by its provider on a "refused" one
sumhook="$work/sumhook.sh"
cat > "$sumhook" <<'HOOK'
#!/usr/bin/env bash
case "${SUM_MODELS:-one}" in
  one) printf 'MODEL model-x\n';;
  differ) printf 'MODEL model-%s\n' "$(printf '%s' "$2" | cksum | cut -d' ' -f1)";;
  some) case "$2" in quiet*) ;; *) printf 'MODEL model-x\n';; esac;;
  none) ;;
esac
[ -z "${SUM_DIRTY:-}" ] || printf 'edited\n' >> "$1/skills/common/probe/SKILL.md"
[ -z "${SUM_DESC_EDIT:-}" ] || sed -i 's/^description: .*/description: "probe two"/' "$1/skills/common/probe/SKILL.md"
[ -z "${SUM_LOCK:-}" ] || chmod 444 "$SUM_LOCK"
case "$2" in
  fire*) printf 'probe\n';;
  refused*) printf 'usage limit exceeded\n';;
esac
HOOK
chmod +x "$sumhook"
sumrun() { # $1 tag, rest: arguments — out in $work/$1.out, summary in $work/$1.json;
  # SUM_ROOT and SUM_HOOK replace the query sets and the session
  local tag="$1"; shift
  DESCRIPTIONS_ROOT="${SUM_ROOT:-$sumdesc}" FAKE_ACTIVATION_HOOK="${SUM_HOOK:-$sumhook}" "$here/bin/triggering" \
    --harness fake --harness-dir "$fake_h" --skill probe --runs 2 --jobs 1 \
    --summary "$work/$tag.json" "$@" > "$work/$tag.out" 2>&1
}

FAKE_VERSION=9.8.7 sumrun sum --plugin "$sumrepo" --json "$work/sum-records.json"; rc=$?
[ "$rc" -eq 1 ] && grep -qF "wrote $work/sum.json" "$work/sum.out" \
  && ok "--summary writes the summary and keeps the sheet's exit code" \
  || bad "--summary writes the summary and keeps the sheet's exit code (rc $rc: $(tail -n 3 "$work/sum.out"))"
jq -e --arg c "$sum_commit" --arg t "$sum_tree" --arg d "$(sha 'description: "probe one"')" '
  .metadata == {skill: "probe", harness: "fake", harness_version: "9.8.7", model: "model-x",
    plugin: {commit: $c, skill_tree: $t}, description_sha256: $d, runs: 2, threshold: 0.5}' \
  "$work/sum.json" >/dev/null 2>&1 \
  && ok "the metadata names the skill text, the description, the CLI, the model, runs and threshold" \
  || bad "the metadata names the skill text, the description, the CLI, the model, runs and threshold ($(jq -c .metadata "$work/sum.json" 2>&1))"
jq -e '
  .splits == {
    train: {queries: 2, passed: 2, failed: 0, inconclusive: 0, pass_rate: 1},
    validation: {queries: 4, passed: 2, failed: 1, inconclusive: 1, pass_rate: (2 / 3)}}' \
  "$work/sum.json" >/dev/null 2>&1 \
  && ok "each split scored is counted; the pass rate leaves the inconclusive out" \
  || bad "each split scored is counted; the pass rate leaves the inconclusive out ($(jq -c .splits "$work/sum.json" 2>&1))"
jq -e '
  .queries == [
    {query: "fire a", should_trigger: true, split: "train", trigger_rate: 1, verdict: "PASS"},
    {query: "quiet b", should_trigger: false, split: "train", trigger_rate: 0, verdict: "PASS"},
    {query: "fire c", should_trigger: true, split: "validation", trigger_rate: 1, verdict: "PASS"},
    {query: "quiet d", should_trigger: false, split: "validation", trigger_rate: 0, verdict: "PASS"},
    {query: "fire wrongly e", should_trigger: false, split: "validation", trigger_rate: 1, verdict: "FAIL"},
    {query: "refused f", should_trigger: true, split: "validation", trigger_rate: null, verdict: "INCONCLUSIVE"}]' \
  "$work/sum.json" >/dev/null 2>&1 \
  && ok "one row per query, in file order, with its rate and verdict" \
  || bad "one row per query, in file order, with its rate and verdict ($(jq -c .queries "$work/sum.json" 2>&1))"
# no transcript, stream, or observed routing enters the summary
jq -e '(keys == ["metadata", "queries", "splits"])
  and all(.queries[]; keys == ["query", "should_trigger", "split", "trigger_rate", "verdict"])' \
  "$work/sum.json" >/dev/null 2>&1 \
  && ! grep -qE 'observed|usage limit|chain|EDIT ' "$work/sum.json" \
  && ok "the summary carries no stream, transcript, or observed routing" \
  || bad "the summary carries no stream, transcript, or observed routing"
# the per-query records are what they were
jq -e 'length == 6 and all(.[]; keys == ["fired", "observed", "query", "rate", "should_trigger", "skill", "split", "valid", "verdict"])' \
  "$work/sum-records.json" >/dev/null 2>&1 \
  && ok "--json beside --summary writes the same per-query records" \
  || bad "--json beside --summary writes the same per-query records ($(jq -c '.[0]' "$work/sum-records.json" 2>&1))"

# a model is one every scored run named; anything else is null, never a guess
SUM_MODELS=differ sumrun sumdiffer --plugin "$sumrepo"
jq -e '.metadata.model == null and .metadata.harness_version == null' "$work/sumdiffer.json" >/dev/null 2>&1 \
  && ok "runs that name different models record a null model; no version read is null" \
  || bad "runs that name different models record a null model; no version read is null ($(jq -c .metadata "$work/sumdiffer.json" 2>&1))"
SUM_MODELS=some sumrun sumsome --plugin "$sumrepo"
jq -e '.metadata.model == null' "$work/sumsome.json" >/dev/null 2>&1 \
  && ok "a model only some scored runs named is null" \
  || bad "a model only some scored runs named is null ($(jq -c .metadata "$work/sumsome.json" 2>&1))"
SUM_MODELS=none sumrun sumnone --plugin "$sumrepo"
jq -e '.metadata.model == null' "$work/sumnone.json" >/dev/null 2>&1 \
  && ok "no model named is null" || bad "no model named is null ($(jq -c .metadata "$work/sumnone.json" 2>&1))"

# a ref is pinned: the summary names the commit it resolved to
git -C "$sumrepo" tag sumtag
SDLC_SKILLS_ROOT="$sumrepo" sumrun sumref --plugin sumtag
jq -e --arg c "$sum_commit" --arg t "$sum_tree" --arg d "$(sha 'description: "probe one"')" '
  .metadata.plugin == {commit: $c, skill_tree: $t} and .metadata.description_sha256 == $d' \
  "$work/sumref.json" >/dev/null 2>&1 \
  && ok "a ref is named by the full commit it was pinned to" \
  || bad "a ref is named by the full commit it was pinned to ($(jq -c .metadata "$work/sumref.json" 2>&1): $(tail -n 2 "$work/sumref.out"))"

# skill text that is no commit's: scored all the same, named by nothing
cp -r "$sumrepo" "$work/sumplain"; rm -rf "$work/sumplain/.git"
sumrun sumplain --plugin "$work/sumplain"; rc=$?
[ "$rc" -eq 1 ] && jq -e --arg d "$(sha 'description: "probe one"')" '
  .metadata.plugin == {commit: null, skill_tree: null} and .metadata.description_sha256 == $d
  and .splits.validation.queries == 4' "$work/sumplain.json" >/dev/null 2>&1 \
  && grep -q 'identity *: .*unidentified.*bin/report' "$work/sumplain.out" \
  && ok "a plugin directory outside git is scored, unnamed, and said so before the run" \
  || bad "a plugin directory outside git is scored, unnamed, and said so before the run (rc $rc: $(jq -c .metadata "$work/sumplain.json" 2>&1))"
cp -r "$sumrepo" "$work/sumdirty"
SUM_DIRTY=1 sumrun sumdirty --plugin "$work/sumdirty"
jq -e '.metadata.plugin == {commit: null, skill_tree: null}' "$work/sumdirty.json" >/dev/null 2>&1 \
  && grep -q 'identity *: .*changed during the run' "$work/sumdirty.out" \
  && ok "a plugin edited during the run ends unidentified" \
  || bad "a plugin edited during the run ends unidentified ($(jq -c .metadata "$work/sumdirty.json" 2>&1))"
# the same for a commit: its checked-out files edited during the run
SDLC_SKILLS_ROOT="$sumrepo" SUM_DIRTY=1 sumrun sumrefdirty --plugin "$sum_commit"
jq -e '.metadata.plugin == {commit: null, skill_tree: null}' "$work/sumrefdirty.json" >/dev/null 2>&1 \
  && grep -q 'identity *: .*changed during the run' "$work/sumrefdirty.out" \
  && ok "a commit whose checked-out files were edited during the run ends unidentified" \
  || bad "a commit whose checked-out files were edited during the run ends unidentified ($(jq -c .metadata "$work/sumrefdirty.json" 2>&1): $(grep '^identity' "$work/sumrefdirty.out"))"
# a tree with no description for the skill has no description hash
sumrun sumnoskill --plugin "$standin"
jq -e '.metadata.description_sha256 == null and .metadata.plugin.skill_tree == null' \
  "$work/sumnoskill.json" >/dev/null 2>&1 \
  && ok "a tree without the skill has a null description hash" \
  || bad "a tree without the skill has a null description hash ($(jq -c .metadata "$work/sumnoskill.json" 2>&1))"

# only the splits that were scored appear
sumrun sumtrain --plugin "$sumrepo" --split train
jq -e '(.splits | keys) == ["train"] and (.queries | length) == 2' "$work/sumtrain.json" >/dev/null 2>&1 \
  && ok "--split train summarizes train alone" \
  || bad "--split train summarizes train alone ($(jq -c .splits "$work/sumtrain.json" 2>&1))"
sumrun sumhold --plugin "$sumrepo" --split holdout
jq -e '.splits == {holdout: {queries: 1, passed: 1, failed: 0, inconclusive: 0, pass_rate: 1}}' \
  "$work/sumhold.json" >/dev/null 2>&1 \
  && ok "--split holdout summarizes the holdout alone" \
  || bad "--split holdout summarizes the holdout alone ($(jq -c .splits "$work/sumhold.json" 2>&1))"

# refused before anything is launched: a summary is one skill's, and its
# directory must exist before the run is paid for
sum_launch="$work/sum-launch.log"
DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
  --harness-dir "$fake_h" --plugin "$sumrepo" --all --runs 1 --summary "$work/sumall.json" >"$work/sumall.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$work/sumall.json" ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary' "$work/sumall.out" \
  && ok "--summary with --all is refused before any launch" \
  || bad "--summary with --all is refused before any launch (rc $rc: $(cat "$work/sumall.out"))"
DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
  --harness-dir "$fake_h" --plugin "$sumrepo" --skill probe --runs 1 \
  --summary "$work/no-such-dir/sum.json" >"$work/sumnodir.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary' "$work/sumnodir.out" \
  && ok "a --summary path in a missing directory is refused before any launch" \
  || bad "a --summary path in a missing directory is refused before any launch (rc $rc: $(cat "$work/sumnodir.out"))"

# a path that begins with - is an option swallowed by mistake, never a file
DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
  --harness-dir "$fake_h" --plugin "$sumrepo" --skill probe --runs 1 --summary --dry-run >"$work/sumopt.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary needs a path' "$work/sumopt.out" \
  && ok "--summary followed by an option is refused: it needs a path" \
  || bad "--summary followed by an option is refused: it needs a path (rc $rc: $(cat "$work/sumopt.out"))"
# what cannot be written is refused before the run, not after it
mkdir -p "$work/sum-is-a-dir"
DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
  --harness-dir "$fake_h" --plugin "$sumrepo" --skill probe --runs 1 \
  --summary "$work/sum-is-a-dir" >"$work/sumisdir.out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary .*is a directory' "$work/sumisdir.out" \
  && ok "a --summary path that is a directory is refused before any launch" \
  || bad "a --summary path that is a directory is refused before any launch (rc $rc: $(tail -n 2 "$work/sumisdir.out"))"
if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$work/sum-readonly"; chmod 555 "$work/sum-readonly"
  DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
    --harness-dir "$fake_h" --plugin "$sumrepo" --skill probe --runs 1 \
    --summary "$work/sum-readonly/sum.json" >"$work/sumro.out" 2>&1; rc=$?
  chmod 755 "$work/sum-readonly"
  [ "$rc" -eq 2 ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary .*cannot be written' "$work/sumro.out" \
    && ok "a --summary path in a read-only directory is refused before any launch" \
    || bad "a --summary path in a read-only directory is refused before any launch (rc $rc: $(tail -n 2 "$work/sumro.out"))"
else
  ok "a --summary path in a read-only directory: not checked as root"
fi

# a commit installed as files that are not its tree's: a plugin checkout set
# to convert line endings checks the commit out converted, so the run scored
# text no tree names
sumconv="$work/sumconv"
git clone -q "$sumrepo" "$sumconv" && git -C "$sumconv" config core.autocrlf true
SDLC_SKILLS_ROOT="$sumconv" sumrun sumconv --plugin "$sum_commit"
jq -e --arg c "$sum_commit" '.metadata.plugin == {commit: $c, skill_tree: null}' "$work/sumconv.json" >/dev/null 2>&1 \
  && grep -q '^identity : unidentified (.*SKILL\.md does not hold the bytes the tree holds.*bin/report' "$work/sumconv.out" \
  && ! grep -q 'the tree changed during the run' "$work/sumconv.out" \
  && ok "a commit installed with converted line endings keeps its commit and names no skill tree, and the run says which file" \
  || bad "a commit installed with converted line endings keeps its commit and names no skill tree, and the run says which file ($(jq -c .metadata "$work/sumconv.json" 2>&1): $(grep '^identity' "$work/sumconv.out"))"

# a skill whose SKILL.md has no description line: scored, and said to be unrecordable
sumnodesc="$work/sumnodesc"
mkdir -p "$sumnodesc/skills/common/probe"
printf -- '---\nname: probe\n---\n\ndescription: body line\n' > "$sumnodesc/skills/common/probe/SKILL.md"
git -C "$sumnodesc" init -q
git -C "$sumnodesc" add -A
git -C "$sumnodesc" -c user.name=t -c user.email=t@example.invalid commit -q -m probe
sumrun sumnodesc --plugin "$sumnodesc"
jq -e '.metadata.description_sha256 == null and (.metadata.plugin.skill_tree | type) == "string"' \
  "$work/sumnodesc.json" >/dev/null 2>&1 \
  && grep -q '^description: unhashed (.*) — bin/report will not record this summary$' "$work/sumnodesc.out" \
  && ok "a SKILL.md with no description line is scored, and the run says the summary cannot be recorded" \
  || bad "a SKILL.md with no description line is scored, and the run says the summary cannot be recorded ($(jq -c .metadata "$work/sumnodesc.json" 2>&1): $(grep '^description' "$work/sumnodesc.out"))"
grep -q '^description: ' "$work/sum.out" \
  && bad "a run that hashed its description prints no description line" \
  || ok "a run that hashed its description prints no description line"

# the plan names the summary and the identity a run would record
out="$(DESCRIPTIONS_ROOT="$sumdesc" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill probe --plugin "$sumrepo" --runs 2 --jobs 1 --split all --timeout 30 --max-turns 4 \
  --json "$work/plan.json" --summary "$work/plan-sum.json" --no-fixture --dry-run 2>&1)"
want="bin/triggering --harness fake --skill probe --plugin $sumrepo --runs 2 --jobs 1 --split all --timeout 30 --max-turns 4 --json $work/plan.json --summary $work/plan-sum.json --no-fixture --harness-dir $fake_h"
[ "$(plan_cmd "$out")" = "$want" ] && [ ! -e "$work/plan-sum.json" ] \
  && ok "the dry run names --summary in the planned invocation and writes nothing" \
  || bad "the dry run names --summary in the planned invocation and writes nothing (got '$(plan_cmd "$out")')"
plan_all="$out"
printf '%s\n' "$out" | grep -q "^identity : $sum_commit  skill_tree $sum_tree\$" \
  && ok "the dry run names the skill text a summary would carry" \
  || bad "the dry run names the skill text a summary would carry (got '$(printf '%s\n' "$out" | grep identity)')"
out="$(DESCRIPTIONS_ROOT="$sumdesc" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill probe --plugin "$work/sumplain" --summary "$work/plan-sum.json" --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q '^identity : unidentified (.*) — bin/report will not record this summary$' \
  && ok "the dry run says when the summary could not be recorded" \
  || bad "the dry run says when the summary could not be recorded (got '$(printf '%s\n' "$out" | grep identity)')"
out="$(DESCRIPTIONS_ROOT="$sumdesc" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill probe --plugin "$sumrepo" --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q '^identity ' \
  && bad "a dry run without --summary prints no identity line" \
  || ok "a dry run without --summary prints no identity line"
# a split without validation cannot be recorded: the plan and the run say so
out="$(DESCRIPTIONS_ROOT="$sumdesc" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill probe --plugin "$sumrepo" --split train --summary "$work/plan-sum.json" --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q '^summary  : no validation split (--split train) — bin/report will not record this summary$' \
  && grep -q '^summary  : no validation split (--split holdout) — bin/report will not record' "$work/sumhold.out" \
  && ok "a summary of train or holdout alone is said to be unrecordable, in the plan and in the run" \
  || bad "a summary of train or holdout alone is said to be unrecordable, in the plan and in the run (got '$(printf '%s\n' "$out" | grep '^summary')')"
{ grep -q '^summary  : ' "$work/sum.out" || grep -q '^summary  : ' <<<"$plan_all"; } \
  && bad "a summary that includes validation prints no such line" \
  || ok "a summary that includes validation prints no such line"
printf '%s\n' "$help_text" | grep -q -- '--summary PATH' \
  && ok "--help documents --summary" || bad "--help documents --summary"

# the seam: what bin/triggering wrote is what bin/report records or refuses
"$here/bin/report" --triggering "$work/sum.json" --record "$work/sumrec" >"$work/sumrec.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && cmp -s "$work/sum.json" "$work/sumrec/triggering.json" \
  && ok "bin/report records a named summary with a failing query" \
  || bad "bin/report records a named summary with a failing query (rc $rc: $(cat "$work/sumrec.out"))"
for t in sumplain:skill_tree sumdirty:skill_tree sumtrain:validation sumhold:validation sumnodesc:description_sha256; do
  "$here/bin/report" --triggering "$work/${t%%:*}.json" --record "$work/${t%%:*}-rec" >"$work/${t%%:*}-rec.out" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$work/${t%%:*}-rec" ] && grep -q "${t##*:}" "$work/${t%%:*}-rec.out" \
    && ok "bin/report refuses the ${t%%:*} summary for its ${t##*:}" \
    || bad "bin/report refuses the ${t%%:*} summary for its ${t##*:} (rc $rc: $(cat "$work/${t%%:*}-rec.out"))"
done

# a description line edited during the run: the summary names no description
cp -r "$sumrepo" "$work/sumdescedit"
SUM_DESC_EDIT=1 sumrun sumdescedit --plugin "$work/sumdescedit"
jq -e '.metadata.description_sha256 == null' "$work/sumdescedit.json" >/dev/null 2>&1 \
  && grep -q '^description: its line changed during the run' "$work/sumdescedit.out" \
  && ok "a description line edited during the run ends unhashed, and the run says so" \
  || bad "a description line edited during the run ends unhashed, and the run says so ($(jq -c .metadata "$work/sumdescedit.json" 2>&1): $(grep '^description' "$work/sumdescedit.out"))"
# ...and an edit that leaves the line alone leaves its hash: the tree changed, the line did not
jq -e --arg d "$(sha 'description: "probe one"')" '.metadata.description_sha256 == $d' \
  "$work/sumdirty.json" >/dev/null 2>&1 && ! grep -q '^description: ' "$work/sumdirty.out" \
  && ok "an edit below the frontmatter leaves the description hash" \
  || bad "an edit below the frontmatter leaves the description hash ($(jq -c .metadata "$work/sumdirty.json" 2>&1))"

# the skill directory with no phase: skills/<skill>
sumflat="$work/sumflat"
mkdir -p "$sumflat/skills/probe"
printf -- '---\nname: probe\ndescription: "probe flat"\n---\n\nbody\n' > "$sumflat/skills/probe/SKILL.md"
git -C "$sumflat" init -q
git -C "$sumflat" add -A
git -C "$sumflat" -c user.name=t -c user.email=t@example.invalid commit -q -m probe
sumrun sumflat --plugin "$sumflat"
jq -e --arg t "$(git -C "$sumflat" rev-parse HEAD:skills/probe)" --arg d "$(sha 'description: "probe flat"')" '
  .metadata.plugin.skill_tree == $t and .metadata.description_sha256 == $d' "$work/sumflat.json" >/dev/null 2>&1 \
  && ok "a skill at skills/<skill> is named by that directory's tree and its description" \
  || bad "a skill at skills/<skill> is named by that directory's tree and its description ($(jq -c .metadata "$work/sumflat.json" 2>&1))"
# two directories for one skill name: no description is the skill's
sumtwo="$work/sumtwo"
cp -r "$sumflat" "$sumtwo"
mkdir -p "$sumtwo/skills/common/probe"
printf -- '---\nname: probe\ndescription: "probe phase"\n---\n' > "$sumtwo/skills/common/probe/SKILL.md"
git -C "$sumtwo" add -A
git -C "$sumtwo" -c user.name=t -c user.email=t@example.invalid commit -q -m two
sumrun sumtwo --plugin "$sumtwo"
jq -e '.metadata.description_sha256 == null' "$work/sumtwo.json" >/dev/null 2>&1 \
  && grep -q '^description: unhashed (the installed tree does not hold exactly one SKILL.md for probe)' "$work/sumtwo.out" \
  && ok "a tree with two SKILL.md for the skill has no description hash, and the run says why" \
  || bad "a tree with two SKILL.md for the skill has no description hash, and the run says why ($(jq -c .metadata "$work/sumtwo.json" 2>&1): $(grep '^description' "$work/sumtwo.out"))"

# rates: exact in the summary, over the conclusive runs, and 0.5 passes neither way
ratedesc="$work/ratedesc"; ratecount="$work/ratecount"
mkdir -p "$ratedesc" "$ratecount"
printf '%s\n' '[{"query":"fire a","should_trigger":true,"split":"train"},
 {"query":"twothirds b","should_trigger":true,"split":"validation"},
 {"query":"half c","should_trigger":true,"split":"validation"},
 {"query":"half d","should_trigger":false,"split":"validation"}]' > "$ratedesc/probe.json"
# the session counts its runs of each query: "twothirds" fires on the first
# two; "half" fires on the first, stays quiet on the second, is refused on the third
ratehook="$work/ratehook.sh"
cat > "$ratehook" <<'HOOK'
#!/usr/bin/env bash
printf 'MODEL model-x\n'
seen="$RATE_COUNT/$(printf '%s' "$2" | cksum | cut -d' ' -f1)"
n=$(( $(cat "$seen" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" > "$seen"
case "$2" in
  fire*) printf 'probe\n';;
  twothirds*) [ "$n" -gt 2 ] || printf 'probe\n';;
  half*) case "$n" in 1) printf 'probe\n';; 3) printf 'usage limit exceeded\n';; esac;;
esac
exit 0
HOOK
chmod +x "$ratehook"
RATE_COUNT="$ratecount" SUM_ROOT="$ratedesc" SUM_HOOK="$ratehook" sumrun sumrate --plugin "$sumrepo" --runs 3
jq -e '.metadata.runs == 3
  and (.queries | map({key: .query, value: [.trigger_rate, .verdict]}) | from_entries) ==
    {"fire a": [1, "PASS"], "twothirds b": [(2/3), "PASS"], "half c": [0.5, "FAIL"], "half d": [0.5, "FAIL"]}
  and .splits.validation == {queries: 3, passed: 1, failed: 2, inconclusive: 0, pass_rate: (1/3)}' \
  "$work/sumrate.json" >/dev/null 2>&1 \
  && ok "trigger_rate and pass_rate are exact, a refused run leaves the denominator, and 0.5 passes neither way" \
  || bad "trigger_rate and pass_rate are exact, a refused run leaves the denominator, and 0.5 passes neither way ($(jq -c '[.queries, .splits]' "$work/sumrate.json" 2>&1))"

# a validation split whose every query was refused: no rate, and still a record
incdesc="$work/incdesc"
mkdir -p "$incdesc"
printf '%s\n' '[{"query":"fire a","should_trigger":true,"split":"train"},
 {"query":"refused b","should_trigger":true,"split":"validation"},
 {"query":"refused c","should_trigger":false,"split":"validation"}]' > "$incdesc/probe.json"
SUM_ROOT="$incdesc" sumrun suminc --plugin "$sumrepo"
jq -e '.splits.validation == {queries: 2, passed: 0, failed: 0, inconclusive: 2, pass_rate: null}
  and ([.queries[] | select(.split == "validation") | [.trigger_rate, .verdict]] | unique) == [[null, "INCONCLUSIVE"]]' \
  "$work/suminc.json" >/dev/null 2>&1 \
  && ok "a split whose every query was refused has a null pass rate and null trigger rates" \
  || bad "a split whose every query was refused has a null pass rate and null trigger rates ($(jq -c '[.queries, .splits]' "$work/suminc.json" 2>&1))"
"$here/bin/report" --triggering "$work/suminc.json" --record "$work/suminc-rec" >"$work/suminc-rec.out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && cmp -s "$work/suminc.json" "$work/suminc-rec/triggering.json" \
  && ok "bin/report records a summary whose validation split was all inconclusive" \
  || bad "bin/report records a summary whose validation split was all inconclusive (rc $rc: $(cat "$work/suminc-rec.out"))"

# the summary file: an earlier one is replaced; one that cannot be written is
# refused before any launch, and said to be lost when it turns so during the run
printf 'stale\n' > "$work/sumover.json"
sumrun sumover --plugin "$sumrepo"
jq -e '.metadata.skill == "probe" and (.queries | length) == 6' "$work/sumover.json" >/dev/null 2>&1 \
  && ok "an existing --summary file is replaced" \
  || bad "an existing --summary file is replaced ($(head -c 200 "$work/sumover.json"))"
if [ "$(id -u)" -ne 0 ]; then
  printf 'stale\n' > "$work/sumrofile.json"; chmod 444 "$work/sumrofile.json"
  DESCRIPTIONS_ROOT="$sumdesc" FAKE_LAUNCH_LOG="$sum_launch" "$here/bin/triggering" --harness fake \
    --harness-dir "$fake_h" --plugin "$sumrepo" --skill probe --runs 1 \
    --summary "$work/sumrofile.json" >"$work/sumrofile.out" 2>&1; rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$sum_launch" ] && grep -q -- '--summary .*cannot be written' "$work/sumrofile.out" \
    && [ "$(cat "$work/sumrofile.json")" = stale ] \
    && ok "an existing read-only --summary file is refused before any launch, and left as it was" \
    || bad "an existing read-only --summary file is refused before any launch, and left as it was (rc $rc: $(tail -n 2 "$work/sumrofile.out"))"
  printf 'stale\n' > "$work/sumlost.json"
  SUM_LOCK="$work/sumlost.json" sumrun sumlost --plugin "$sumrepo"; rc=$?
  [ "$rc" -eq 2 ] && grep -q "^could not write --summary $work/sumlost.json\$" "$work/sumlost.out" \
    && ! grep -q '^wrote .*sumlost.json' "$work/sumlost.out" && [ "$(cat "$work/sumlost.json")" = stale ] \
    && ok "a --summary file that turns read-only during the run is said to be unwritten, exit 2" \
    || bad "a --summary file that turns read-only during the run is said to be unwritten, exit 2 (rc $rc: $(tail -n 3 "$work/sumlost.out"))"
else
  ok "an existing read-only --summary file: not checked as root"
  ok "a --summary file that turns read-only during the run: not checked as root"
fi

# --- no invented monetary cost ----------------------------------------------
#
# The offline paths report the plan, never a price. The pattern is a
# currency symbol followed by a digit, or a three-letter currency code —
# the pricing LANGUAGE the help carries ("COST:", "priced") is not a
# figure and is not matched.

money_re='(\$[0-9])|(\bUSD\b)|(\bEUR\b)|(\bGBP\b)|(€)|(£)'
for text in "$("$here/bin/triggering" --help 2>&1)" \
            "$("$here/bin/triggering" --harness fake --skill yagni --dry-run 2>&1)"; do
  if printf '%s\n' "$text" | grep -qE "$money_re"; then
    bad "the help and the dry run carry no monetary figure"
  else
    ok "the help and the dry run carry no monetary figure"
  fi
done

# --- a CLI that has exited is not waited on ----------------------------------
#
# While the CLI runs, the runner reads its chain every two seconds. A CLI
# that has already exited is not held for the rest of that interval: six
# runs of the fake, which exits at once and routes nowhere, take less than
# six intervals. FAKE_FIRE=0 keeps the other way out of the wait, the
# subject showing up in the chain, out of this case.

t0="$SECONDS"
DESCRIPTIONS_ROOT="$iso" FAKE_FIRE=0 "$here/bin/triggering" "${base[@]}" \
  --skill probe --split all --runs 3 --jobs 1 --json "$work/poll.json" >/dev/null 2>&1
took="$(( SECONDS - t0 ))"
ran="$(jq '[.[].valid] | add' "$work/poll.json" 2>/dev/null)"
[ "$ran" = 6 ] && [ "$took" -lt 12 ] \
  && ok "six runs of a CLI that exits at once take less than six poll intervals" \
  || bad "six runs of a CLI that exits at once take less than six poll intervals (${ran:-no} runs scored in ${took}s)"

# --- a CLI that is still running when its run is scored is stopped ----------
#
# The runner leaves the wait as soon as the subject shows up in the chain.
# The CLI may still be working then: FAKE_MODE=linger emits its chain and
# stays, and records its pid. The process that stands for the CLI is not
# the runner's own job but three levels below it, as a real CLI is (the
# launch subshell, `timeout`, the CLI), so stopping the job alone leaves it
# running, in a home the runner then removes.

linger_log="$work/linger.pids"
: > "$linger_log"
t0="$SECONDS"
DESCRIPTIONS_ROOT="$iso" FAKE_MODE=linger FAKE_SUBJECT=probe FAKE_LINGER_LOG="$linger_log" \
  "$here/bin/triggering" "${base[@]}" \
  --skill probe --split all --runs 1 --jobs 1 --timeout 60 --json "$work/linger.json" >/dev/null 2>&1
took="$(( SECONDS - t0 ))"
ran="$(jq '[.[].valid] | add' "$work/linger.json" 2>/dev/null)"
launched="$(wc -l < "$linger_log" | tr -d ' ')"
[ "$ran" = 2 ] && [ "$launched" = 2 ] && [ "$took" -lt 30 ] \
  && ok "a run whose subject fired is scored without waiting for the CLI to end" \
  || bad "a run whose subject fired is scored without waiting for the CLI to end (${ran:-no} runs scored, ${launched} launched, ${took}s)"
# A stopped process may take a moment to go: three seconds, read ten times a second.
left=""
for _ in $(seq 1 30); do
  left=""
  while read -r lpid; do
    kill -0 "$lpid" 2>/dev/null && left="$left $lpid"
  done < "$linger_log"
  [ -z "$left" ] && break
  sleep 0.1
done
if [ -z "$left" ] && [ "$launched" = 2 ]; then
  ok "no CLI is left running once its run is scored"
else
  bad "no CLI is left running once its run is scored (still running:${left:- none}; ${launched} launched)"
  # shellcheck disable=SC2086
  [ -z "$left" ] || kill $left 2>/dev/null
fi

# --- the non-launching paths -------------------------------------------------
#
# A sentinel real CLI stands on PATH: it fails and records that it was
# called. The help and the dry run must never reach it.

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

"$here/bin/triggering" --help >/dev/null 2>&1
"$here/bin/triggering" --harness opencode --skill yagni --dry-run >/dev/null 2>&1
[ ! -f "$sentinel_log" ] && ok "help and the dry run call no CLI" \
  || bad "help and the dry run call no CLI (the sentinel was called)"

# the control: the live path DOES reach the CLI, so the case above is not
# vacuous. The sentinel fails, so nothing is spent.
DESCRIPTIONS_ROOT="$work/descriptions" \
  "$here/bin/triggering" --harness opencode --skill probe --plugin "$standin" \
  --runs 1 --split train >/dev/null 2>&1
[ -f "$sentinel_log" ] && ok "the live path reaches the CLI (the control)" \
  || bad "the live path reaches the CLI (the control)"

exit "$fails"
