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
#
# A token is a path the corpus names when it looks like one: it ends in a file
# extension, or it names a directory the staged tree has at its top. Every
# root is covered — a query that names `skills/…` or `scripts/…` is naming a
# path like any other, and a check that excluded those roots would report a
# guarantee it does not give. A slash-separated list in prose ("json/yaml/
# table", a branch name) names no file, and is left out by the same rule.
_staged_paths() { # $1 descriptions root, $2 the staged tree
  local descs="$1" staged="$2" tok last ext top
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    last="${tok##*/}"
    ext="${last##*.}"
    if [ "$ext" != "$last" ]; then
      case "$ext" in [A-Za-z]*) printf '%s\n' "$tok"; continue ;; esac
    fi
    top="${tok%%/*}"
    [ -e "$staged/$top" ] && printf '%s\n' "$tok"
  done < <(
    find "$descs" -name '*.json' -type f ! -path '*/holdout/*' | sort \
      | while IFS= read -r f; do jq -r '.[].query' "$f"; done \
      | tr ' \t' '\n\n' | tr -d "\'" \
      | awk '{ gsub(/[`",;:!?()\[\]{}<>]/, ""); sub(/\.$/, ""); print }' \
      | grep -E '^[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@-]+)+$' \
      | sort -u
  )
}

expect_fail() { # $1 label, $2 the message the failure must carry
  if [ "$check_rc" -eq 0 ]; then
    bad "$1 (the gate accepted it)"
  elif grep -qF "$2" <<< "$check_out"; then
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

# The mutation cases run the gate several at once. The gate stops at its first
# failure, so each mutation needs a run of its own; the runs share nothing
# (each reads its own copy, and its temporary files come from mktemp), so
# they need not wait for one another. gate_rejects starts a case's run, at
# most one per core at a time; report_gates waits for them all and judges
# each in the order the cases were written, so the output reads the same as
# if they had run one after another.
gate_max="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
gate_n=0
gate_reaped=0
gate_pids=()
gate_labels=()
gate_messages=()

gate_rejects() { # $1 root, $2 label, $3 the message the failure must carry, then VAR=value for the gate
  local root="$1" i="$gate_n"
  gate_labels[i]="$2"
  gate_messages[i]="$3"
  shift 3
  if [ $((i - gate_reaped)) -ge "$gate_max" ]; then
    wait "${gate_pids[gate_reaped]}"
    gate_reaped=$((gate_reaped + 1))
  fi
  {
    ( cd "$root" && env "$@" bash bin/check ) >"$work/gate.$i.out" 2>&1
    echo "$?" >"$work/gate.$i.rc"
  } &
  gate_pids[i]=$!
  gate_n=$((i + 1))
}

report_gates() {
  local i
  wait
  for ((i = 0; i < gate_n; i++)); do
    check_rc="$(cat "$work/gate.$i.rc" 2>/dev/null)"
    check_out="$(cat "$work/gate.$i.out" 2>/dev/null)"
    case "$check_rc" in
      ''|*[!0-9]*) bad "${gate_labels[i]} (the gate left no exit status)" ;;
      *) expect_fail "${gate_labels[i]}" "${gate_messages[i]}" ;;
    esac
  done
}

# --- the committed corpora ---------------------------------------------------

run_gate "$here"
expect_pass "the committed corpora pass the gate"
if grep -q "^check: corpora ok$" <<< "$check_out"; then
  ok "the gate says the corpora are ok"
else
  bad "the gate says the corpora are ok"
fi

n_skills="$(jq '.skills | length' "$INV")"
n_desc="$(find descriptions -maxdepth 1 -name '*.json' -type f | wc -l | tr -d ' ')"
n_evals="$(find evals -mindepth 2 -maxdepth 2 -name evals.json -type f | wc -l | tr -d ' ')"
if [ "$n_desc" -eq "$n_skills" ] && [ "$n_evals" -eq "$n_skills" ]; then
  ok "every skill the inventory holds carries a query set and an eval definition ($n_skills of each)"
else
  bad "every skill the inventory holds carries a query set and an eval definition ($n_desc sets, $n_evals definitions, $n_skills skills)"
fi

# the layout is flat: a set is descriptions/<skill>.json and a definition is
# evals/<skill>/evals.json, with no phase directory above either, and the
# retired scenario tree is gone
phase_dirs="$(find descriptions -mindepth 1 -maxdepth 1 -type d ! -name holdout | sort | tr '\n' ' ')"
if [ -z "$phase_dirs" ] && [ ! -e behavior ]; then
  ok "the corpora are flat, with no phase directory and no behavior/ tree"
else
  bad "the corpora are flat, with no phase directory and no behavior/ tree (dirs: ${phase_dirs:-none}; behavior/ $( [ -e behavior ] && echo present || echo absent ))"
fi
while IFS= read -r sk; do
  if [ -f "descriptions/$sk.json" ] && [ -f "evals/$sk/evals.json" ]; then :; else
    bad "the $sk corpus is at descriptions/$sk.json and evals/$sk/evals.json"
  fi
done < <(jq -r '.skills[]' "$INV")

# the two sets v11.2.0 added and the one 12.0.0 added never name their own
# skill: a query or a prompt that says the skill's name tests the name, not
# the description
for sk in brainstorming eliminating-corrections runtime-evidence; do
  named=0
  if [ -f "descriptions/$sk.json" ] \
      && grep -qiF "$sk" < <(jq -r '.[].query' "descriptions/$sk.json"); then named=1; fi
  if [ -f "evals/$sk/evals.json" ] \
      && grep -qiF "$sk" < <(jq -r '.evals[].prompt' "evals/$sk/evals.json"); then named=1; fi
  if [ -f "descriptions/$sk.json" ] && [ -f "evals/$sk/evals.json" ] && [ "$named" -eq 0 ]; then
    ok "no $sk query or prompt names its own skill"
  else
    bad "no $sk query or prompt names its own skill"
  fi
done

# every set is at least twenty queries and every eval holds two or three
small_set=0
while IFS= read -r f; do
  n="$(jq 'length' "$f")"
  [ "$n" -ge 20 ] || { small_set=1; printf '       %s holds %s queries\n' "$f" "$n"; }
done < <(find descriptions -maxdepth 1 -name '*.json' -type f | sort)
if [ "$small_set" -eq 0 ]; then
  ok "every query set holds at least twenty queries"
else
  bad "every query set holds at least twenty queries"
fi

small_eval=0
while IFS= read -r f; do
  n="$(jq '.evals | length' "$f")"
  { [ "$n" -ge 2 ] && [ "$n" -le 3 ]; } || { small_eval=1; printf '       %s holds %s cases\n' "$f" "$n"; }
done < <(find evals -mindepth 2 -maxdepth 2 -name evals.json -type f | sort)
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
done < <(find evals -mindepth 2 -maxdepth 2 -name evals.json -type f | sort)
if [ "$missing_files" -eq 0 ]; then
  ok "every eval definition carries its own fixture tree"
else
  bad "every eval definition carries its own fixture tree"
fi

# --- the mutations that prove the gate bites ---------------------------------
#
# Each mutation is applied to a throwaway copy and the gate must reject it.
# Every copy is a directory of its own: the gate may still be reading one
# while the next case is built.

# 1. a skill is removed: its description set goes, and the coverage list is
#    no longer closed
m1="$work/m1"; copy_repo "$m1"
rm -f "$m1/descriptions/yagni.json"
gate_rejects "$m1" "a removed skill is rejected" "no description set for yagni"

# 1b. a skill is removed on the output side
m1b="$work/m1b"; copy_repo "$m1b"
rm -f "$m1b/evals/yagni/evals.json"
gate_rejects "$m1b" "a removed eval definition is rejected" "no evals.json for yagni"

# 2. a stale skill: a corpus asset for a skill the inventory does not hold
m2="$work/m2"; copy_repo "$m2"
cp "$m2/descriptions/yagni.json" "$m2/descriptions/a-skill-that-was-removed.json"
gate_rejects "$m2" "a stale skill's query set is rejected" "names a skill the inventory does not hold"

m2b="$work/m2b"; copy_repo "$m2b"
mkdir -p "$m2b/evals/a-skill-that-was-removed"
cp "$m2b/evals/yagni/evals.json" \
   "$m2b/evals/a-skill-that-was-removed/evals.json"
gate_rejects "$m2b" "a stale skill's eval definition is rejected" "names a skill the inventory does not hold"

# 2c. a set under a retired phase directory is read by no runner
m2c="$work/m2c"; copy_repo "$m2c"
mkdir -p "$m2c/descriptions/common"
cp "$m2c/descriptions/yagni.json" "$m2c/descriptions/common/yagni.json"
gate_rejects "$m2c" "a query set under a phase directory is rejected" "descriptions/common/yagni.json is not at"

# 2d. a skill the inventory holds is found however long the inventory is.
# The lookup once read the list through a pipe into `grep -q`: grep left at
# the match, the writer was killed on the closed pipe, and under pipefail
# that read as "not a skill". A list longer than a pipe holds makes that
# happen every time instead of now and then under load. The gate still
# fails here, on the first padding name, which the coverage record's corpus
# state does not hold: a rule it reaches only after every corpus asset and
# every route was found in the list.
m2d="$work/m2d"; copy_repo "$m2d"
jq '.skills += [range(0; 12000) | "zz-a-name-that-pads-the-list-\(.)"]' "$m2d/$INV" \
  > "$m2d/$INV.new"
mv "$m2d/$INV.new" "$m2d/$INV"
gate_rejects "$m2d" "a skill the inventory holds is found in a long inventory" \
  "zz-a-name-that-pads-the-list-0 is neither frozen nor named as new"

# 3. a duplicated query inside a set
m3="$work/m3"; copy_repo "$m3"
jq '.[1].query = .[0].query' "$m3/descriptions/yagni.json" > "$m3/descriptions/yagni.json.new"
mv "$m3/descriptions/yagni.json.new" "$m3/descriptions/yagni.json"
gate_rejects "$m3" "a duplicated query is rejected" "has duplicate queries"

# 3b. a set too small to decide anything: ten positives and ten near misses
#     is twenty queries, so a set that loses a near miss loses that too
m3b="$work/m3b"; copy_repo "$m3b"
jq 'del(.[19])' "$m3b/descriptions/yagni.json" > "$m3b/descriptions/yagni.json.new"
mv "$m3b/descriptions/yagni.json.new" "$m3b/descriptions/yagni.json"
gate_rejects "$m3b" "a query set holding fewer than ten near misses is rejected" "needs >= 10 negatives"

# 4. validation leaks into the holdout role, and the holdout role leaks
#    back into a main set
m4="$work/m4"; copy_repo "$m4"
mkdir -p "$m4/descriptions/holdout"
# the holdout file holds five fresh queries and repeats one of the set's
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    + [.[0] | .split = "holdout"]' "$m4/descriptions/yagni.json" > "$m4/descriptions/holdout/yagni.json"
gate_rejects "$m4" "a holdout that reuses a main set's query is rejected" "reuses queries from"

m4b="$work/m4b"; copy_repo "$m4b"
mkdir -p "$m4b/descriptions/holdout"
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    | .[0].split = "validation"' "$m4b/descriptions/yagni.json" \
  > "$m4b/descriptions/holdout/yagni.json"
gate_rejects "$m4b" "a holdout carrying a validation split is rejected" "must carry split=holdout"

m4c="$work/m4c"; copy_repo "$m4c"
jq '.[0].split = "holdout"' "$m4c/descriptions/yagni.json" > "$m4c/descriptions/yagni.json.new"
mv "$m4c/descriptions/yagni.json.new" "$m4c/descriptions/yagni.json"
gate_rejects "$m4c" "a main set carrying a holdout entry is rejected" "carries a holdout entry"

# 5. an output case names a file its fixture tree does not hold
m5="$work/m5"; copy_repo "$m5"
jq '.evals[0].prompt = "Refactor src/a-file-that-is-not-there.js so it stops re-parsing the auth header."' \
  "$m5/evals/yagni/evals.json" > "$m5/evals/yagni/evals.json.new"
mv "$m5/evals/yagni/evals.json.new" "$m5/evals/yagni/evals.json"
gate_rejects "$m5" "an output case naming a missing file is rejected" "names a file its fixture tree does not hold"

# 6. a corrupted eval structure
m6="$work/m6"; copy_repo "$m6"
jq 'del(.evals[0].expected_output)' "$m6/evals/yagni/evals.json" \
  > "$m6/evals/yagni/evals.json.new"
mv "$m6/evals/yagni/evals.json.new" "$m6/evals/yagni/evals.json"
gate_rejects "$m6" "an eval with no expected output is rejected" "needs an id, a prompt, an expected output"

m6b="$work/m6b"; copy_repo "$m6b"
jq '.evals = .evals[0:1]' "$m6b/evals/yagni/evals.json" \
  > "$m6b/evals/yagni/evals.json.new"
mv "$m6b/evals/yagni/evals.json.new" "$m6b/evals/yagni/evals.json"
gate_rejects "$m6b" "an eval holding one case is rejected" "holds 2-3 output cases"

m6c="$work/m6c"; copy_repo "$m6c"
jq '.skill_name = "some-other-skill"' "$m6c/evals/yagni/evals.json" \
  > "$m6c/evals/yagni/evals.json.new"
mv "$m6c/evals/yagni/evals.json.new" "$m6c/evals/yagni/evals.json"
gate_rejects "$m6c" "an eval naming another skill is rejected" "names a skill that is not its own"

m6d="$work/m6d"; copy_repo "$m6d"
jq '.pending_first_run = true | .evals[0].assertions = ["[check:file-exists src/server.js]"]' \
  "$m6d/evals/yagni/evals.json" > "$m6d/evals/yagni/evals.json.new"
mv "$m6d/evals/yagni/evals.json.new" "$m6d/evals/yagni/evals.json"
gate_rejects "$m6d" "an unobserved case carrying an assertion is rejected" "must carry empty assertions"

m6e="$work/m6e"; copy_repo "$m6e"
jq '.evals[0].prompt = "In ~/work/billing-api the toggle command is done. Call this done."' \
  "$m6e/evals/yagni/evals.json" > "$m6e/evals/yagni/evals.json.new"
mv "$m6e/evals/yagni/evals.json.new" "$m6e/evals/yagni/evals.json"
gate_rejects "$m6e" "an output case naming a project outside the workdir is rejected" "names a project outside the run workdir"

# 7. a near miss that routes to a skill the inventory does not hold
m7c="$work/m7c"; copy_repo "$m7c"
jq '.[10].expect = "a-skill-that-does-not-exist"' "$m7c/descriptions/yagni.json" \
  > "$m7c/descriptions/yagni.json.new"
mv "$m7c/descriptions/yagni.json.new" "$m7c/descriptions/yagni.json"
gate_rejects "$m7c" "a near miss routing to an unknown skill is rejected" "names a route that is not a skill"

# 8. an eval definition with no fixture tree
m8="$work/m8"; copy_repo "$m8"
rm -rf "$m8/evals/yagni/files"
gate_rejects "$m8" "an eval definition with no fixture tree is rejected" "has no files/ tree"

# 9. the seams the gate reads: the holdout cross-check follows the
#    descriptions root, and the docs rule follows the docs root
m9="$work/m9"; copy_repo "$m9"
mkdir -p "$m9/seam-descriptions/holdout"
cp "$m9/descriptions/yagni.json" "$m9/seam-descriptions/yagni.json"
jq '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]
    + [.[0] | .split = "holdout"]' "$m9/seam-descriptions/yagni.json" > "$m9/seam-descriptions/holdout/yagni.json"
gate_rejects "$m9" "the holdout cross-check follows the descriptions root seam" "reuses queries from" \
  DESCRIPTIONS_ROOT=seam-descriptions

m9b="$work/m9b"; copy_repo "$m9b"
mkdir -p "$m9b/seam-docs"
cp "$m9b/docs/upstream-coverage.md" "$m9b/seam-docs/upstream-coverage.md"
printf '# a record\n' > "$m9b/seam-docs/record.md"
chmod +x "$m9b/seam-docs/record.md"
gate_rejects "$m9b" "the docs no-exec-bit rule follows the docs root seam" "executable under docs/" \
  DOCS_ROOT=seam-docs

# the eval definitions follow their own root: a case broken only under the
# moved root is caught, so the gate reads that root and not evals/
m9c="$work/m9c"; copy_repo "$m9c"
cp -a "$m9c/evals" "$m9c/seam-evals"
jq 'del(.evals[0].expected_output)' "$m9c/seam-evals/yagni/evals.json" \
  > "$m9c/seam-evals/yagni/evals.json.new"
mv "$m9c/seam-evals/yagni/evals.json.new" "$m9c/seam-evals/yagni/evals.json"
gate_rejects "$m9c" "the eval definitions follow the evals root seam" "needs an id, a prompt, an expected output" \
  EVALS_ROOT=seam-evals

# A rule that reads a long listing through `writer | grep -q` stops reading
# at the first match; the writer then dies of SIGPIPE, pipefail reports 141,
# and the `if` reads "no match". Each case below puts the match first and
# writes far more than a pipe holds after it, so a cut pipe passes the gate.
long_name="$(printf 'r%.0s' $(seq 100))"
m9d="$work/m9d"; copy_repo "$m9d"
head -c 1048576 /dev/zero | tr '\0' 'a' > "$work/filler.txt"
jq --rawfile filler "$work/filler.txt" \
  '.evals[0].prompt = "In ~/work/billing-api the toggle command is done. Call this done."
   | .evals[1].prompt += " " + $filler' \
  "$m9d/evals/yagni/evals.json" > "$m9d/evals/yagni/evals.json.new"
mv "$m9d/evals/yagni/evals.json.new" "$m9d/evals/yagni/evals.json"
gate_rejects "$m9d" "a home path in the first prompt is rejected when a long prompt follows it" \
  "names a project outside the run workdir"

m9e="$work/m9e"; copy_repo "$m9e"
mkdir -p "$m9e/seam-docs/many"
cp "$m9e/docs/upstream-coverage.md" "$m9e/seam-docs/upstream-coverage.md"
for i in $(seq 3000); do : > "$m9e/seam-docs/many/$long_name-$i.md"; done
chmod +x "$m9e"/seam-docs/many/*
gate_rejects "$m9e" "the docs no-exec-bit rule holds when thousands of files carry the bit" "executable under docs/" \
  DOCS_ROOT=seam-docs

m9f="$work/m9f"; copy_repo "$m9f"
mkdir -p "$m9f/seam-docs/many"
cp "$m9f/docs/upstream-coverage.md" "$m9f/seam-docs/upstream-coverage.md"
for i in $(seq 3000); do printf '#!/bin/sh\n' > "$m9f/seam-docs/many/$long_name-$i.md"; done
gate_rejects "$m9f" "the docs no-shebang rule holds when thousands of files carry one" "shebang under docs/" \
  DOCS_ROOT=seam-docs

# --- bin/ holds executable bash scripts only ----------------------------------
#
# Every file under bin/ is a tool a user runs by path. A file there that is
# not executable, or that names another interpreter, is a tool that does not
# run the way its neighbours do.
m9g="$work/m9g"; copy_repo "$m9g"
printf '#!/usr/bin/env bash\necho a tool\n' > "$m9g/bin/not-executable"
chmod -x "$m9g/bin/not-executable"
gate_rejects "$m9g" "a bin/ file that is not executable is rejected" "bin/not-executable is not executable"

m9h="$work/m9h"; copy_repo "$m9h"
printf '#!/bin/sh\necho a tool\n' > "$m9h/bin/another-shell"
chmod +x "$m9h/bin/another-shell"
gate_rejects "$m9h" "a bin/ file without the bash shebang is rejected" "bin/another-shell does not start with #!/usr/bin/env bash"

m9i="$work/m9i"; copy_repo "$m9i"
printf '# notes about the tools\n' > "$m9i/bin/NOTES.md"
gate_rejects "$m9i" "a non-script file under bin/ is rejected" "bin/NOTES.md is not executable"

# --- the corpus state the gate holds against ---------------------------------
#
# The gate reads the coverage record: the frozen per-entry split assignment,
# the selections that have happened, and the corpus audit's own numbers. Each
# of these cases breaks one of them and expects the gate's refusal.

# E-1, first direction: a case carries an assertion and the definition
# records no observation state. The gate cannot know where the assertion came
# from, and a fabricated one would be graded against a real run.
m10="$work/m10"; copy_repo "$m10"
jq 'del(.pending_first_run) | .evals[0].assertions = ["[check:file-exists src/server.js]"]' \
  "$m10/evals/yagni/evals.json" > "$m10/evals/yagni/evals.json.new"
mv "$m10/evals/yagni/evals.json.new" "$m10/evals/yagni/evals.json"
gate_rejects "$m10" "a case with an assertion and no observation state is rejected" \
  "carries an assertion but records no observation state"

# E-1, second direction: the same assertion added to a case that is still
# pending its first run. A different message, because the fault is different.
m11="$work/m11"; copy_repo "$m11"
jq '.evals[0].assertions = ["[check:file-exists src/server.js]"]' \
  "$m11/evals/yagni/evals.json" > "$m11/evals/yagni/evals.json.new"
mv "$m11/evals/yagni/evals.json.new" "$m11/evals/yagni/evals.json"
gate_rejects "$m11" "a case with an assertion while pending its first run is rejected" \
  "is pending its first run and must carry empty assertions"

# E-2: two entries of a frozen set swap splits. The ratios the shape check
# reads stay the same, so only the frozen assignment catches it.
m12="$work/m12"; copy_repo "$m12"
jq '.[0].split = "validation" | .[5].split = "train"' \
  "$m12/descriptions/yagni.json" > "$m12/descriptions/yagni.json.new"
mv "$m12/descriptions/yagni.json.new" "$m12/descriptions/yagni.json"
gate_rejects "$m12" "an entry that moves between splits is rejected" \
  "does not hold the frozen split assignment"

# E-2, second direction: an entry moves into the holdout role.
m13="$work/m13"; copy_repo "$m13"
jq '.[0].split = "holdout"' "$m13/descriptions/yagni.json" \
  > "$m13/descriptions/yagni.json.new"
mv "$m13/descriptions/yagni.json.new" "$m13/descriptions/yagni.json"
gate_rejects "$m13" "an entry moved into the holdout role is rejected" \
  "carries a holdout entry"

# E-4: the staged plan's approval row, and the task file its index names.
# Each is a required staged input, and the gate refuses without it.
m14="$work/m14"; copy_repo "$m14"
rm -f "$m14/fixtures/seed/plans/2026-10-05-multi-tenancy/00-index.ledger.md"
gate_rejects "$m14" "a staged plan with no approval row is rejected" \
  "the staged plan 2026-10-05-multi-tenancy carries no ledger"

m15="$work/m15"; copy_repo "$m15"
rm -f "$m15/fixtures/seed/plans/2026-10-05-multi-tenancy/01-tenant-column.md"
gate_rejects "$m15" "a staged plan with a missing task file is rejected" \
  "names a task file it does not hold"

# E-5: the corpus audit's own numbers. A row that no longer recomputes is a
# false claim in the record.
m16="$work/m16"; copy_repo "$m16"
sed -i 's#| `yagni` | `skills/common/yagni/SKILL.md` | 10 | 10 |#| `yagni` | `skills/common/yagni/SKILL.md` | 9 | 10 |#' \
  "$m16/docs/upstream-coverage.md"
gate_rejects "$m16" "a corpus audit row whose numbers no longer recompute is rejected" \
  "states 9 positives and the set holds another number"

# E-6: a holdout file placed in the corpus before the selection step. It is
# a falsely untouched test set, and the gate refuses it.
m17="$work/m17"; copy_repo "$m17"
mkdir -p "$m17/descriptions/holdout"
jq -n '[range(5) | {query: "a fresh holdout query \(.)", should_trigger: false, split: "holdout", expect: "none"}]' \
  > "$m17/descriptions/holdout/yagni.json"
gate_rejects "$m17" "a holdout placed before the selection step is rejected" \
  "names no recorded selection"

report_gates

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

probe_desc="$work/probe-descriptions"
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
  if [ -f "$snapshot/.agent/sessions/2026-10-14-charge-flow.ndjson" ]; then
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
  done < <(_staged_paths "$here/descriptions" "$snapshot")
  if [ "$missing" -eq 0 ]; then
    ok "every path a query names is staged"
  else
    bad "every path a query names is staged ($missing missing)"
  fi

  # The check above must be able to see a path nothing stages, whatever its
  # root: a query that names `skills/…` names a path like any other. So a
  # query naming one is rejected, and the rejection is shown here rather than
  # assumed.
  seam_desc="$work/seam-descriptions"
  rm -rf "$seam_desc"; cp -a "$here/descriptions" "$seam_desc"
  jq '.[0].query = "Edit skills/testing/security-audits/SKILL.md — the body is too long and rambles."' \
    "$seam_desc/writing-skills.json" > "$seam_desc/writing-skills.json.new"
  mv "$seam_desc/writing-skills.json.new" "$seam_desc/writing-skills.json"
  seam_missing=0
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ -e "$snapshot/$tok" ] && continue
    seam_missing=$((seam_missing + 1))
  done < <(_staged_paths "$seam_desc" "$snapshot")
  if [ "$seam_missing" -gt 0 ]; then
    ok "a query naming a path nothing stages is rejected, whatever its root"
  else
    bad "a query naming a path nothing stages is rejected, whatever its root"
  fi

  # The transcript the diagnosis case grades has to carry the edit the case
  # expects. A case that grades a transcript against a map the transcript
  # does not match measures nothing, so the paths the case names are read
  # back out of the transcript itself.
  transcript="$snapshot/.agent/sessions/2026-10-14-charge-flow.ndjson"
  diag_case="$here/evals/diagnosing-a-session/evals.json"
  graded=0
  graded_missing=0
  for tok in $(jq -r '.evals[] | select(.id == "why-did-it-change-tax") | .expected_output' \
      "$diag_case" 2>/dev/null \
      | tr ' \t' '\n\n' | tr -d "\'" \
      | awk '{ gsub(/[`",;:!?()\[\]{}<>]/, ""); sub(/\.$/, ""); print }' \
      | grep -E '^[A-Za-z0-9_.@-]+(/[A-Za-z0-9_.@-]+)+$' | sort -u); do
    [ -e "$here/evals/diagnosing-a-session/files/$tok" ] || continue
    graded=$((graded + 1))
    # The path has to be the one the EDIT landed on, not merely one the
    # transcript mentions: a transcript whose edit lands on another file
    # disagrees with the map the case grades, and the case then measures
    # nothing.
    grep -qF "$tok" < <(grep -iE 'edit' "$transcript" 2>/dev/null) \
      || graded_missing=$((graded_missing + 1))
  done
  if [ "$graded" -gt 0 ] && [ "$graded_missing" -eq 0 ]; then
    ok "the staged transcript carries the edit the diagnosis case grades ($graded paths)"
  else
    bad "the staged transcript carries the edit the diagnosis case grades ($graded named, $graded_missing missing)"
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
