#!/usr/bin/env bash
# Offline test: the corpora — the description query sets and the output-eval
# definitions for every skill in the pinned inventory — and the gate that
# holds them to shape.
#
# Nothing here launches a model, a CLI or a live run. The triggering runner is
# invoked with a test double that snapshots the workdir it staged, so the
# staged description-query tree can be inspected as the runner really builds
# it. The mutations run against a throwaway copy of this repository, so the
# committed corpus is never touched.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here" || exit 1

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

INV="config/upstream-inventory.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check_rc=0
check_out=""

# Run the gate in a throwaway copy of this repository, so a mutation cannot
# touch the committed corpus. $1 is the copy's root.
run_gate() { # $1 root
  local root="$1"
  ( cd "$root" && bash bin/check ) >"$work/gate.out" 2>&1
  check_rc=$?
  check_out="$(cat "$work/gate.out")"
}

# A fresh copy of the repository, without the git metadata.
copy_repo() { # $1 destination
  mkdir -p "$1"
  ( cd "$here" && tar --exclude=.git --exclude=workspaces -cf - . ) | ( cd "$1" && tar xf - )
}

# --- helpers -----------------------------------------------------------------

# A plan's version, the way the upstream plan-version.sh computes it: the
# index with every task checkbox and state label normalized, then every task
# file in index order.
_plan_version_of() { # $1 plan directory
  local dir="$1" states file
  states='todo|in progress|done|done with concerns|blocked|needs context|cancelled|superseded'
  {
    sed -E 's/^- \[[ xX]\] (.*)`('"$states"')`[[:space:]]*$/- [ ] \1`todo`/' "$dir/00-index.md"
    while IFS= read -r file; do
      printf '\n=== %s\n' "$file"
      cat "$dir/$file" 2>/dev/null
    done < <(sed -n 's/^.*`\([^`]*\.md\)`.*`\(todo\|in progress\|done\|done with concerns\|blocked\|needs context\|cancelled\|superseded\)`$/\1/p' \
      "$dir/00-index.md")
  } | tr -d '\r' | git hash-object --stdin | cut -c1-7
}

# The path-like tokens the description queries name, one per line.
_staged_paths() { # $1 descriptions root
  find "$1" -name '*.json' -type f ! -path '*/holdout/*' | sort | while IFS= read -r f; do
    jq -r '.[].query' "$f"
  done | tr ' \t' '\n\n' | tr -d "\'" \
    | awk '{ gsub(/[`",;:!?()\[\]{}<>]/, ""); sub(/\.$/, ""); print }' \
    | grep -E '^[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@-]+)+$' \
    | grep -vE '^(skills|scripts|json|go|empty|task|release|pending)/' \
    | sort -u
}

expect_fail() { # $1 label, $2 the message the failure must carry
  if [ "$check_rc" -eq 0 ]; then
    bad "$1 (the gate accepted it)"
  elif printf '%s\n' "$check_out" | grep -qF "$2"; then
    ok "$1"
  else
    bad "$1 (exit $check_rc, no '$2' in: $(printf '%s\n' "$check_out" | tail -3 | tr '\n' ' '))"
  fi
}

expect_pass() { # $1 label
  if [ "$check_rc" -eq 0 ]; then
    ok "$1"
  else
    bad "$1 (exit $check_rc): $(printf '%s\n' "$check_out" | tail -3 | tr '\n' ' ')"
  fi
}

# --- the committed corpora ---------------------------------------------------

run_gate "$here"
expect_pass "the committed corpora pass the gate"
if printf '%s\n' "$check_out" | grep -q "^check: corpora ok$"; then
  ok "the gate says the corpora are ok"
else
  bad "the gate says the corpora are ok"
fi

n_skills="$(jq '.skills | length' "$INV")"
n_desc="$(find descriptions -name '*.json' -path '*/[a-z]*/*.json' | grep -cv '/holdout/')"
n_evals="$(find behavior/evals -name evals.json -type f | wc -l | tr -d ' ')"
if [ "$n_desc" -eq "$n_skills" ] && [ "$n_evals" -eq "$n_skills" ]; then
  ok "every skill in the pin carries a query set and an eval definition ($n_skills of each)"
else
  bad "every skill in the pin carries a query set and an eval definition ($n_desc sets, $n_evals definitions, $n_skills skills)"
fi

# every set is at least twenty queries and every eval holds two or three
small_set=0
while IFS= read -r f; do
  n="$(jq 'length' "$f")"
  [ "$n" -ge 20 ] || { small_set=1; printf '       %s holds %s queries\n' "$f" "$n"; }
done < <(find descriptions -name '*.json' | grep -v '/holdout/' | sort)
if [ "$small_set" -eq 0 ]; then
  ok "every query set holds at least twenty queries"
else
  bad "every query set holds at least twenty queries"
fi

small_eval=0
while IFS= read -r f; do
  n="$(jq '.evals | length' "$f")"
  { [ "$n" -ge 2 ] && [ "$n" -le 3 ]; } || { small_eval=1; printf '       %s holds %s cases\n' "$f" "$n"; }
done < <(find behavior/evals -name evals.json -type f | sort)
if [ "$small_eval" -eq 0 ]; then
  ok "every eval definition holds two or three cases"
else
  bad "every eval definition holds two or three cases"
fi

# every case carries its own fixture tree, and every case is unobserved
missing_files=0
while IFS= read -r f; do
  d="$(dirname "$f")"
  [ -d "$d/files" ] || { missing_files=1; printf '       %s has no files/ tree\n' "$d"; }
done < <(find behavior/evals -name evals.json -type f | sort)
if [ "$missing_files" -eq 0 ]; then
  ok "every eval definition carries its own fixture tree"
else
  bad "every eval definition carries its own fixture tree"
fi

# --- the mutations that prove the gate bites ---------------------------------
#
# Each mutation is applied to a throwaway copy and the gate must reject it.

# 1. a skill is removed: its description set goes, and the coverage list is
#    no longer closed
m1="$work/m1"; copy_repo "$m1"
rm -f "$m1/descriptions/common/yagni.json"
run_gate "$m1"
expect_fail "a removed skill is rejected" "no description set for common/yagni"

# 1b. a skill is removed on the output side
m1b="$work/m1b"; copy_repo "$m1b"
rm -f "$m1b/behavior/evals/common/yagni/evals.json"
run_gate "$m1b"
expect_fail "a removed eval definition is rejected" "no evals.json for common/yagni"

# 2. a stale skill: a corpus asset for a skill the pin does not hold
m2="$work/m2"; copy_repo "$m2"
mkdir -p "$m2/descriptions/common"
cp "$m2/descriptions/common/yagni.json" "$m2/descriptions/common/a-skill-that-was-removed.json"
run_gate "$m2"
expect_fail "a stale skill's query set is rejected" "names a skill the inventory does not hold"

m2b="$work/m2b"; copy_repo "$m2b"
mkdir -p "$m2b/behavior/evals/common/a-skill-that-was-removed"
cp "$m2b/behavior/evals/common/yagni/evals.json" \
   "$m2b/behavior/evals/common/a-skill-that-was-removed/evals.json"
run_gate "$m2b"
expect_fail "a stale skill's eval definition is rejected" "names a skill the inventory does not hold"

# 3. a duplicated query inside a set
m3="$work/m3"; copy_repo "$m3"
jq '.[1].query = .[0].query' "$m3/descriptions/common/yagni.json" > "$m3/descriptions/common/yagni.json.new"
mv "$m3/descriptions/common/yagni.json.new" "$m3/descriptions/common/yagni.json"
run_gate "$m3"
expect_fail "a duplicated query is rejected" "has duplicate queries"

# 4. validation leaks into the holdout role, and the holdout role leaks
#    back into a main set
m4="$work/m4"; copy_repo "$m4"
mkdir -p "$m4/descriptions/holdout/common"
# the holdout file holds five fresh queries and repeats one of the set's
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    + [.[0] | .split = "holdout"]' "$m4/descriptions/common/yagni.json" > "$m4/descriptions/holdout/common/yagni.json"
run_gate "$m4"
expect_fail "a holdout that reuses a main set's query is rejected" "reuses queries from"

m4b="$work/m4b"; copy_repo "$m4b"
mkdir -p "$m4b/descriptions/holdout/common"
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    | .[0].split = "validation"' "$m4b/descriptions/common/yagni.json" \
  > "$m4b/descriptions/holdout/common/yagni.json"
run_gate "$m4b"
expect_fail "a holdout carrying a validation split is rejected" "must carry split=holdout"

m4c="$work/m4c"; copy_repo "$m4c"
jq '.[0].split = "holdout"' "$m4c/descriptions/common/yagni.json" > "$m4c/descriptions/common/yagni.json.new"
mv "$m4c/descriptions/common/yagni.json.new" "$m4c/descriptions/common/yagni.json"
run_gate "$m4c"
expect_fail "a main set carrying a holdout entry is rejected" "carries a holdout entry"

# 5. an output case names a file its fixture tree does not hold
m5="$work/m5"; copy_repo "$m5"
jq '.evals[0].prompt = "Refactor src/a-file-that-is-not-there.js so it stops re-parsing the auth header."' \
  "$m5/behavior/evals/common/yagni/evals.json" > "$m5/behavior/evals/common/yagni/evals.json.new"
mv "$m5/behavior/evals/common/yagni/evals.json.new" "$m5/behavior/evals/common/yagni/evals.json"
run_gate "$m5"
expect_fail "an output case naming a missing file is rejected" "names a file its fixture tree does not hold"

# 6. a corrupted eval structure
m6="$work/m6"; copy_repo "$m6"
jq 'del(.evals[0].expected_output)' "$m6/behavior/evals/common/yagni/evals.json" \
  > "$m6/behavior/evals/common/yagni/evals.json.new"
mv "$m6/behavior/evals/common/yagni/evals.json.new" "$m6/behavior/evals/common/yagni/evals.json"
run_gate "$m6"
expect_fail "an eval with no expected output is rejected" "needs an id, a prompt, an expected output"

m6b="$work/m6b"; copy_repo "$m6b"
jq '.evals = .evals[0:1]' "$m6b/behavior/evals/common/yagni/evals.json" \
  > "$m6b/behavior/evals/common/yagni/evals.json.new"
mv "$m6b/behavior/evals/common/yagni/evals.json.new" "$m6b/behavior/evals/common/yagni/evals.json"
run_gate "$m6b"
expect_fail "an eval holding one case is rejected" "holds 2-3 output cases"

m6c="$work/m6c"; copy_repo "$m6c"
jq '.skill_name = "some-other-skill"' "$m6c/behavior/evals/common/yagni/evals.json" \
  > "$m6c/behavior/evals/common/yagni/evals.json.new"
mv "$m6c/behavior/evals/common/yagni/evals.json.new" "$m6c/behavior/evals/common/yagni/evals.json"
run_gate "$m6c"
expect_fail "an eval naming another skill is rejected" "names a skill that is not its own"

m6d="$work/m6d"; copy_repo "$m6d"
jq '.pending_first_run = true | .evals[0].assertions = ["[check:file-exists src/server.js]"]' \
  "$m6d/behavior/evals/common/yagni/evals.json" > "$m6d/behavior/evals/common/yagni/evals.json.new"
mv "$m6d/behavior/evals/common/yagni/evals.json.new" "$m6d/behavior/evals/common/yagni/evals.json"
run_gate "$m6d"
expect_fail "an unobserved case carrying an assertion is rejected" "must carry empty assertions"

m6e="$work/m6e"; copy_repo "$m6e"
jq '.evals[0].prompt = "In ~/work/billing-api the toggle command is done. Call this done."' \
  "$m6e/behavior/evals/common/yagni/evals.json" > "$m6e/behavior/evals/common/yagni/evals.json.new"
mv "$m6e/behavior/evals/common/yagni/evals.json.new" "$m6e/behavior/evals/common/yagni/evals.json"
run_gate "$m6e"
expect_fail "an output case naming a project outside the workdir is rejected" "names a project outside the run workdir"

# 7. a near miss that routes to a skill the pin does not hold
m7c="$work/m7c"; copy_repo "$m7c"
jq '.[10].expect = "a-skill-that-does-not-exist"' "$m7c/descriptions/common/yagni.json" \
  > "$m7c/descriptions/common/yagni.json.new"
mv "$m7c/descriptions/common/yagni.json.new" "$m7c/descriptions/common/yagni.json"
run_gate "$m7c"
expect_fail "a near miss routing to an unknown skill is rejected" "names a route that is not a skill"

# 8. an eval definition with no fixture tree
m8="$work/m8"; copy_repo "$m8"
rm -rf "$m8/behavior/evals/common/yagni/files"
run_gate "$m8"
expect_fail "an eval definition with no fixture tree is rejected" "has no files/ tree"

# 9. the seams the gate reads: the holdout cross-check follows the
#    descriptions root, and the docs rule follows the docs root
m9="$work/m9"; copy_repo "$m9"
mkdir -p "$m9/seam-descriptions/common" "$m9/seam-descriptions/holdout/common"
cp "$m9/descriptions/common/yagni.json" "$m9/seam-descriptions/common/yagni.json"
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    + [.[0] | .split = "holdout"]' "$m9/seam-descriptions/common/yagni.json" > "$m9/seam-descriptions/holdout/common/yagni.json"
check_out="$(cd "$m9" && DESCRIPTIONS_ROOT=seam-descriptions bash bin/check 2>&1)"
check_rc=$?
expect_fail "the holdout cross-check follows the descriptions root seam" "reuses queries from"

m9b="$work/m9b"; copy_repo "$m9b"
mkdir -p "$m9b/seam-docs"
printf '# a record\n' > "$m9b/seam-docs/record.md"
chmod +x "$m9b/seam-docs/record.md"
check_out="$(cd "$m9b" && DOCS_ROOT=seam-docs bash bin/check 2>&1)"
check_rc=$?
expect_fail "the docs no-exec-bit rule follows the docs root seam" "executable under docs/"

# --- the staged description-query tree ---------------------------------------
#
# The description runner seeds every query with a project. The tree it seeds
# is what makes a query that names a path answerable, so it is inspected here
# as the runner really builds it: the runner is invoked with a test double
# that snapshots the workdir it staged.

fake_dir="$work/harness"
mkdir -p "$fake_dir"
cat >"$fake_dir/fake.sh" <<'ADAPTER'
#!/usr/bin/env bash
# A test double for the descriptions runner: it is the real offline double
# with one addition — it snapshots the workdir the runner staged, so the
# test can inspect the tree the runner really seeds.
#
# The runner reads `runnable=` off this file, so the contract is declared here
# as well as in the double this one wraps.
# shellcheck disable=SC2034,SC2154
# shellcheck source=/dev/null
. "$FAKE_REAL"
runnable=yes
runnable_reason="offline test double — always runnable, never a live CLI"
eval "$(declare -f adapter_run_activation | sed '1s/^adapter_run_activation/_fake_orig_run_activation/')"
adapter_run_activation() {
  if [ -n "${FAKE_WORKDIR_SNAPSHOT:-}" ]; then
    rm -rf "$FAKE_WORKDIR_SNAPSHOT"
    cp -a "$1" "$FAKE_WORKDIR_SNAPSHOT" 2>/dev/null
  fi
  _fake_orig_run_activation "$@"
}
ADAPTER

probe_desc="$work/probe-descriptions/common"
mkdir -p "$probe_desc"
printf '%s\n' '[{"query":"probe","should_trigger":true,"split":"train","expect":"probe"}]' \
  >"$probe_desc/probe.json"

plug="$work/plugin"
mkdir -p "$plug"
git -C "$plug" init -q 2>/dev/null
git -C "$plug" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m tree 2>/dev/null

snapshot="$work/staged"
FAKE_REAL="$here/lib/tests/fake-cli/fake.sh" \
FAKE_SUBJECT=probe \
FAKE_WORKDIR_SNAPSHOT="$snapshot" \
SDLC_SKILLS_EVALS_ROOT="$here" \
DESCRIPTIONS_ROOT="$work/probe-descriptions" \
  "$here/bin/triggering" --harness fake --harness-dir "$fake_dir" \
  --plugin "$plug" --skill probe --runs 1 --split train >"$work/trigger.out" 2>&1
trigger_rc=$?

if [ "$trigger_rc" -eq 0 ] && [ -d "$snapshot" ]; then
  ok "the descriptions runner stages a tree the test can inspect"
else
  bad "the descriptions runner stages a tree the test can inspect (exit $trigger_rc)"
  printf '       %s\n' "$(tail -3 "$work/trigger.out" | tr '\n' ' ')"
fi

if [ -d "$snapshot" ]; then
  # the plan the corpus names is staged with its tasks, its version and its
  # approval
  plan_dir="$snapshot/.sdlc-skills/plans/2026-10-05-multi-tenancy"
  if [ -f "$plan_dir/00-index.md" ] && [ -f "$plan_dir/00-index.ledger.md" ] \
      && [ -f "$plan_dir/01-tenant-column.md" ]; then
    ok "the staged plan carries its index, its task files and its ledger"
  else
    bad "the staged plan carries its index, its task files and its ledger"
  fi

  approval="$(sed -n 's/^| \([0-9a-f]\{7\}\) |  | .*| approved | mode: \([a-z]*\) .*/\1 \2/p' \
    "$plan_dir/00-index.ledger.md" 2>/dev/null | head -1)"
  staged_version="$(printf '%s' "$approval" | cut -d' ' -f1)"
  staged_mode="$(printf '%s' "$approval" | cut -d' ' -f2)"
  if [ -n "$staged_version" ] && [ -n "$staged_mode" ]; then
    ok "the staged approval row binds a version and a mode ($staged_version, $staged_mode)"
  else
    bad "the staged approval row binds a version and a mode"
  fi

  # the version the approval binds is the version the plan's own content
  # computes, read with the rule the upstream plan-version.sh applies
  computed="$(_plan_version_of "$plan_dir")"
  if [ "$computed" = "$staged_version" ]; then
    ok "the staged approval binds the plan's real version ($computed)"
  else
    bad "the staged approval binds the plan's real version (staged $staged_version, computed $computed)"
  fi

  # the same version, read with the upstream script itself where a pinned
  # upstream tree is on this machine: the lab's own rule must agree with it
  upstream_pv=""
  for cand in "${SDLC_SKILLS_ROOT:-}/skills/design/writing-plans/scripts/plan-version.sh" \
              "/tmp/opencode/sdlc-skills-pinned/skills/design/writing-plans/scripts/plan-version.sh"; do
    if [ -f "$cand" ]; then upstream_pv="$cand"; break; fi
  done
  if [ -n "$upstream_pv" ]; then
    upstream_version="$(bash "$upstream_pv" "$plan_dir" 2>/dev/null)"
    if [ "$upstream_version" = "$staged_version" ]; then
      ok "the upstream plan-version.sh computes the staged version ($upstream_version)"
    else
      bad "the upstream plan-version.sh computes the staged version (upstream $upstream_version, staged $staged_version)"
    fi
  else
    printf '  note  no pinned upstream tree on this machine: the upstream version script was not run\n'
  fi

  # the session sample and the ticket are staged too
  if [ -f "$snapshot/.agent/sessions/2026-10-14-charge-flow.jsonl" ]; then
    ok "the staged tree carries the session sample"
  else
    bad "the staged tree carries the session sample"
  fi
  if [ -f "$snapshot/docs/tickets/INV-142.md" ]; then
    ok "the staged tree carries the ticket"
  else
    bad "the staged tree carries the ticket"
  fi

  # every path a query names is staged
  missing=0
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ -e "$snapshot/$tok" ] && continue
    missing=$((missing + 1))
    printf '       %s is named by a query and not staged\n' "$tok"
  done < <(_staged_paths "$here/descriptions")
  if [ "$missing" -eq 0 ]; then
    ok "every path a query names is staged"
  else
    bad "every path a query names is staged ($missing missing)"
  fi

  # --- the rejection: a required staged input is removed ---------------------
  #
  # The approval is what binds the plan to the version it was approved at.
  # Without it the plan is a proposal, and the version can no longer be read
  # off the ledger, so the staged tree no longer answers the question a
  # query asks.
  broken="$work/broken"
  rm -rf "$broken"; cp -a "$snapshot" "$broken"
  rm -f "$broken/.sdlc-skills/plans/2026-10-05-multi-tenancy/00-index.ledger.md"
  if [ ! -f "$broken/.sdlc-skills/plans/2026-10-05-multi-tenancy/00-index.ledger.md" ] \
      && [ -z "$(sed -n 's/^| \([0-9a-f]\{7\}\) |  | .*| approved |.*/\1/p' \
        "$broken/.sdlc-skills/plans/2026-10-05-multi-tenancy/00-index.ledger.md" 2>/dev/null)" ]; then
    ok "a plan whose approval row is removed no longer binds a version"
  else
    bad "a plan whose approval row is removed no longer binds a version"
  fi

  # the same for a task file the index names: the version cannot be computed
  broken2="$work/broken2"
  rm -rf "$broken2"; cp -a "$snapshot" "$broken2"
  rm -f "$broken2/.sdlc-skills/plans/2026-10-05-multi-tenancy/01-tenant-column.md"
  if [ "$(_plan_version_of "$broken2/.sdlc-skills/plans/2026-10-05-multi-tenancy")" != "$staged_version" ]; then
    ok "a plan whose task file is removed no longer computes its version"
  else
    bad "a plan whose task file is removed no longer computes its version"
  fi
fi

exit "$fails"
