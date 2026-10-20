#!/usr/bin/env bash
# Offline test: the committed upstream inventory, the gate that enforces it,
# and the mutations that prove the gate rejects a broken one. The plugin tree
# is a fixture built here — no network, no upstream checkout, no live run.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here" || exit 1

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

INV="config/upstream-inventory.json"
DOC="docs/upstream-coverage.md"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

check_rc=0
check_out=""

run_check() { # $1 inventory path, $2 docs root, rest: extra bin/check arguments
  local inv="$1" docs="$2"
  shift 2
  check_out="$(INVENTORY_PATH="$inv" DOCS_ROOT="$docs" bash bin/check --inventory "$@" 2>&1)" \
    && check_rc=0 || check_rc=$?
}

run_check_full() { # $1 inventory path, $2 docs root — the whole gate, no --inventory
  local inv="$1" docs="$2"
  check_out="$(INVENTORY_PATH="$inv" DOCS_ROOT="$docs" bash bin/check 2>&1)" \
    && check_rc=0 || check_rc=$?
}

run_check_ci() { # the gate exactly as CI runs it: no environment override at
  # all: the three roots are unset for the child, so an environment that
  # exports them cannot redirect the run at another artifact
  check_out="$(env -u INVENTORY_PATH -u DOCS_ROOT -u DESCRIPTIONS_ROOT bash bin/check 2>&1)" \
    && check_rc=0 || check_rc=$?
}

record_field() { # $1 the table row's label — the number that row states
  sed -n "s/^| $1 | \([0-9][0-9]*\).*/\1/p" "$DOC" | head -1
}

record_heading_count() { # $1 the heading text — the count its heading states
  sed -n "s/^### $1 (\([0-9][0-9]*\))$/\1/p" "$DOC" | head -1
}

record_bullets() { # $1 the heading text — the paths the section under it lists
  awk -v h="$1" '
    index($0, "### " h " (") == 1 { inside = 1; next }
    inside && /^##/ { inside = 0 }
    inside && /^- `/ {
      line = $0
      sub(/^- `/, "", line)
      sub(/`.*$/, "", line)
      print line
    }' "$DOC"
}

expect_pass() { # $1 label
  if [ "$check_rc" -eq 0 ]; then
    ok "$1"
  else
    bad "$1 (exit $check_rc): $(printf '%s\n' "$check_out" | tail -2 | tr '\n' ' ')"
  fi
}

expect_fail() { # $1 label, $2 the message the failure must carry
  if [ "$check_rc" -eq 0 ]; then
    bad "$1 (the gate accepted it)"
  elif printf '%s\n' "$check_out" | grep -qF "$2"; then
    ok "$1"
  else
    bad "$1 (exit $check_rc, no '$2' in: $(printf '%s\n' "$check_out" | tail -2 | tr '\n' ' '))"
  fi
}

mutate() { # $1 jq filter, $2 output path — the output must stay valid JSON
  if ! jq "$1" "$INV" >"$2" 2>/dev/null || ! jq -e . "$2" >/dev/null 2>&1; then
    bad "the mutation is not valid JSON: $1"
    return 1
  fi
  return 0
}

# --- the committed artifacts exist -----------------------------------------

if [ -f "$INV" ]; then
  ok "the upstream inventory is committed"
else
  bad "the upstream inventory is committed ($INV)"
  exit 1
fi
if jq -e . "$INV" >/dev/null 2>&1; then
  ok "the upstream inventory is valid JSON"
else
  bad "the upstream inventory is valid JSON"
fi
if [ -f "$DOC" ]; then
  ok "the coverage record is committed"
else
  bad "the coverage record is committed ($DOC)"
fi

# --- the gate refuses what it cannot trust ---------------------------------

run_check "$work/there-is-no-such-inventory.json" docs
expect_fail "a missing inventory file is rejected" "no upstream inventory"

# --- the committed inventory passes -----------------------------------------

run_check "$INV" docs
expect_pass "the committed inventory passes the gate"

# the default path says what it did NOT check: membership is knowable only
# against a tree
if printf '%s\n' "$check_out" | grep -q "membership not checked"; then
  ok "the default path says membership was not checked"
else
  bad "the default path says membership was not checked"
fi

# the partial run says which sections it ran, so its result cannot be read
# as a full-gate pass
if printf '%s\n' "$check_out" | grep -q "pinned scope only"; then
  ok "the partial run says it ran the pinned scope only"
else
  bad "the partial run says it ran the pinned scope only"
fi

# the default CI path runs the inventory check: a missing inventory fails
# the whole gate, not only the --inventory mode
run_check_full "$work/there-is-no-such-inventory.json" docs
expect_fail "the default CI path runs the inventory check" "no upstream inventory"

# the gate as CI runs it: no environment override, so the committed
# inventory and the committed record are the ones that are checked
run_check_ci
expect_pass "the gate passes the way CI runs it"
if printf '%s\n' "$check_out" | grep -q "^check: inventory ok$" \
    && printf '%s\n' "$check_out" | grep -q "^check: OK$"; then
  ok "the CI-shaped run resolves the committed inventory and ends with check: OK"
else
  bad "the CI-shaped run resolves the committed inventory and ends with check: OK"
fi

# The CI-shaped run is the invocation CI performs, so an environment that
# exports a root override must not redirect it at another artifact. The
# probe exports three overrides that point nowhere and runs the helper in
# a subshell, so the probe's own exports never reach the rest of the
# suite and never reach the run that follows it.
probe_rc_file="$work/ci-probe.rc"
probe_out_file="$work/ci-probe.out"
(
  export INVENTORY_PATH="$work/there-is-no-such-inventory.json"
  export DOCS_ROOT="$work/there-are-no-docs"
  export DESCRIPTIONS_ROOT="$work/there-are-no-descriptions"
  run_check_ci
  printf '%s\n' "$check_rc" >"$probe_rc_file"
  printf '%s\n' "$check_out" >"$probe_out_file"
)
probe_rc="$(cat "$probe_rc_file")"
if [ "$probe_rc" -eq 0 ]; then
  ok "the CI-shaped run ignores the environment's overrides"
else
  bad "the CI-shaped run ignores the environment's overrides (exit $probe_rc): $(tail -2 "$probe_out_file" | tr '\n' ' ')"
fi

# --- drift against a tree built from the inventory --------------------------

tree="$work/tree"
mkdir -p "$tree/skills" "$tree/tests/harnesses"
while IFS= read -r sk; do
  mkdir -p "$tree/skills/$sk"
  : >"$tree/skills/$sk/SKILL.md"
done < <(jq -r '.skills[]' "$INV")
while IFS= read -r h; do
  : >"$tree/tests/harnesses/$h.sh"
done < <(jq -r '.harnesses[]' "$INV")

run_check "$INV" docs --plugin "$tree"
expect_pass "the inventory matches a tree built from it"

# the with-tree path says what it did not verify: the comparison is by
# name, so the tree's commit and its contents are not established
if printf '%s\n' "$check_out" | grep -q "compared by name" \
    && printf '%s\n' "$check_out" | grep -q "were not verified"; then
  ok "the with-tree path says what it did not verify"
else
  bad "the with-tree path says what it did not verify"
fi

# a packaged mirror carries the same skills flat — it is a distribution
# artifact, never a second canonical copy
mirror="$work/mirror-tree"
cp -r "$tree" "$mirror"
mkdir -p "$mirror/plugins/sdlc-skills/skills"
while IFS= read -r sk; do
  name="$(basename "$sk")"
  mkdir -p "$mirror/plugins/sdlc-skills/skills/$name"
  : >"$mirror/plugins/sdlc-skills/skills/$name/SKILL.md"
done < <(jq -r '.skills[]' "$INV")
run_check "$INV" docs --plugin "$mirror"
expect_pass "a packaged mirror is not counted as a canonical skill"

# the upstream tree carries a README.md beside its harnesses: it is not a
# harness, at any depth
readme_tree="$work/readme-tree"
cp -r "$tree" "$readme_tree"
printf '# upstream harnesses\n' >"$readme_tree/tests/harnesses/README.md"
mkdir -p "$readme_tree/tests/harnesses/nested"
printf '# nested\n' >"$readme_tree/tests/harnesses/nested/README.md"
run_check "$INV" docs --plugin "$readme_tree"
expect_pass "a tree's harness README is not collected as a harness"

# --- mutations of the inventory are rejected --------------------------------

# membership is only knowable against a tree: the tree still carries the
# member the inventory dropped
if mutate 'del(.skills[0])' "$work/m.json"; then
  run_check "$work/m.json" docs --plugin "$tree"
  expect_fail "a missing skill member is rejected" "absent from the inventory"
fi
if mutate 'del(.harnesses[0])' "$work/m.json"; then
  run_check "$work/m.json" docs --plugin "$tree"
  expect_fail "a missing harness member is rejected" "absent from the inventory"
fi
if mutate '.skills += [.skills[0]]' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a duplicate skill member is rejected" "skill rows must be unique"
fi
if mutate '.harnesses += [.harnesses[0]]' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a duplicate harness member is rejected" "harness rows must be unique"
fi
if mutate '.skills |= map(if . == "analysis/working-from-a-ticket" then "analysis/working-from-ticket" else . end)' "$work/m.json"; then
  run_check "$work/m.json" docs --plugin "$tree"
  expect_fail "a mismatched canonical skill name is rejected" "absent from the supplied tree"
fi
if mutate '.skills |= map(if . == "analysis/working-from-a-ticket" then "working-from-a-ticket" else . end)' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a skill row that is not a canonical path is rejected" "skill rows must be canonical paths"
fi
if mutate '.skills |= reverse' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "skill rows out of canonical order are rejected" "skill rows must be in canonical (sorted) order"
fi
if mutate '.upstream.commit = "0000000000000000000000000000000000000000"' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a rewritten upstream commit is rejected" "does not pin"
fi
if mutate '.upstream.commit = "v11.0.0"' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a version tag instead of a commit is rejected" "does not pin"
fi
if mutate '.upstream.version = "10.2.1"' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a wrong package version is rejected" "does not pin"
fi
if mutate '.upstream.url = "https://example.invalid/sdlc-skills"' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a wrong upstream repository is rejected" "does not pin"
fi
if mutate 'del(.upstream)' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "an inventory without a pin is rejected" "does not pin"
fi

# --- mutations of the tree are rejected -------------------------------------

drift_tree="$work/drift-tree"
cp -r "$tree" "$drift_tree"
rm -rf "$drift_tree/skills/$(jq -r '.skills[0]' "$INV")"
run_check "$INV" docs --plugin "$drift_tree"
expect_fail "a tree that lost a skill is rejected" "absent from the supplied tree"

drift_tree2="$work/drift-tree2"
cp -r "$tree" "$drift_tree2"
mkdir -p "$drift_tree2/skills/testing/a-skill-that-does-not-exist"
: >"$drift_tree2/skills/testing/a-skill-that-does-not-exist/SKILL.md"
run_check "$INV" docs --plugin "$drift_tree2"
expect_fail "a tree that gained a skill is rejected" "absent from the inventory"

drift_tree3="$work/drift-tree3"
cp -r "$tree" "$drift_tree3"
rm -f "$drift_tree3/tests/harnesses/$(jq -r '.harnesses[0]' "$INV").sh"
run_check "$INV" docs --plugin "$drift_tree3"
expect_fail "a tree that lost a harness is rejected" "absent from the supplied tree"

drift_tree4="$work/drift-tree4"
cp -r "$tree" "$drift_tree4"
: >"$drift_tree4/tests/harnesses/a-harness-that-does-not-exist.sh"
run_check "$INV" docs --plugin "$drift_tree4"
expect_fail "a tree that gained a harness is rejected" "absent from the inventory"

# a member of a supplied tree is never invisible: a skill outside the
# canonical two-level shape is drift, not a path to discard
drift_tree5="$work/drift-tree5"
cp -r "$tree" "$drift_tree5"
mkdir -p "$drift_tree5/skills/design/newphase/newskill"
: >"$drift_tree5/skills/design/newphase/newskill/SKILL.md"
run_check "$INV" docs --plugin "$drift_tree5"
expect_fail "a tree skill outside the canonical shape is rejected" "absent from the inventory"

# the same rule for harnesses: a harness outside the flat
# tests/harnesses/*.sh shape is drift too
drift_tree6="$work/drift-tree6"
cp -r "$tree" "$drift_tree6"
mkdir -p "$drift_tree6/tests/harnesses/nested"
: >"$drift_tree6/tests/harnesses/nested/brand-new-harness.sh"
run_check "$INV" docs --plugin "$drift_tree6"
expect_fail "a tree harness outside the flat shape is rejected" "absent from the inventory"

# a drifting tree: the disclosure belongs on the failure path too, and the
# message must not claim the tree is upstream
drift_tree7="$work/drift-tree7"
cp -r "$tree" "$drift_tree7"
mkdir -p "$drift_tree7/skills/design/newphase/newskill"
: >"$drift_tree7/skills/design/newphase/newskill/SKILL.md"
run_check "$INV" docs --plugin "$drift_tree7"
expect_fail "a drifting tree is rejected" "absent from the inventory"
if printf '%s\n' "$check_out" | grep -q "were not verified"; then
  ok "the failure path carries the not-verified disclosure"
else
  bad "the failure path carries the not-verified disclosure"
fi
if printf '%s\n' "$check_out" | grep -q "upstream tree"; then
  bad "the failure path does not claim the tree is upstream"
else
  ok "the failure path does not claim the tree is upstream"
fi

# two tree files sharing a basename are one member, not two
dup_tree="$work/dup-tree"
cp -r "$tree" "$dup_tree"
mkdir -p "$dup_tree/tests/harnesses/nested"
: >"$dup_tree/tests/harnesses/nested/opencode.sh"
run_check "$INV" docs --plugin "$dup_tree"
expect_pass "a repeated harness basename is one member"
if printf '%s\n' "$check_out" | grep -q "absent from the inventory"; then
  bad "a repeated harness basename is not reported as drift"
else
  ok "a repeated harness basename is not reported as drift"
fi

# a tree file whose name strips to nothing is a member, not an absence
empty_name_tree="$work/empty-name-tree"
cp -r "$tree" "$empty_name_tree"
: >"$empty_name_tree/tests/harnesses/.sh"
run_check "$INV" docs --plugin "$empty_name_tree"
expect_fail "a tree file with an empty name is drift" "absent from the inventory"
if printf '%s\n' "$check_out" | grep -q "an empty name"; then
  ok "the drift report names an empty member readably"
else
  bad "the drift report names an empty member readably"
fi

# An empty list is not a list holding an empty member. A tree that has
# the two directories and no members in them is drift: the report names
# the inventory's members as absent, and it carries no blank member line
# for the tree's empty list.
#
# The empty-list half of the gate's helper is invisible in that report:
# the empty line the helper would print is the only line of an empty
# list, so the command substitution that holds the report strips it, and
# the tree's members are collected with an empty name rewritten rather
# than kept. The helper is therefore read from the gate's own file and
# run, and the case asserts both halves: the report, and the helper's
# own contract.
empty_tree="$work/empty-tree"
mkdir -p "$empty_tree/skills" "$empty_tree/tests/harnesses"
run_check "$INV" docs --plugin "$empty_tree"
list_lines_fn="$(sed -n '/^_list_lines() {/,/^}/p' bin/check)"
empty_list_lines=""
if [ -n "$list_lines_fn" ]; then
  empty_list_lines="$(printf '%s\n%s\n' "$list_lines_fn" '_list_lines "" | wc -l' \
    | bash 2>/dev/null | tr -d '[:space:]')"
fi
if [ "$empty_list_lines" = "0" ] \
    && [ "$check_rc" -ne 0 ] \
    && printf '%s\n' "$check_out" | grep -qF "in the inventory, absent from the supplied tree:" \
    && printf '%s\n' "$check_out" | grep -qF "$(jq -r '.skills[0]' "$INV")" \
    && ! printf '%s\n' "$check_out" | grep -qE '^[[:space:]]+$'; then
  ok "an empty tree is drift with no blank member line, and an empty list prints no line"
else
  bad "an empty tree is drift with no blank member line, and an empty list prints no line (exit $check_rc, empty list lines: '$empty_list_lines')"
fi

# --- the coverage record maps every old task --------------------------------

if [ -f "$DOC" ]; then
  mkdir -p "$work/docs"
  grep -v '^| E-7 ' "$DOC" >"$work/docs/upstream-coverage.md"
  run_check "$INV" "$work/docs"
  expect_fail "a coverage record that drops a task mapping is rejected" "does not map E-7"

  # the default CI path reaches the record check: a valid inventory and a
  # record that lost a row must fail the whole gate
  run_check_full "$INV" "$work/docs"
  expect_fail "the default CI path checks the coverage record" "does not map E-7"

  # the mapping is read from the Verdict cell: a verdict word in another
  # cell of the row does not satisfy it
  mkdir -p "$work/docs-empty-verdict"
  awk -F'|' 'BEGIN { OFS = "|" } $2 ~ /^ E-0 / { $3 = " removed "; $4 = " " } { print }' \
    "$DOC" >"$work/docs-empty-verdict/upstream-coverage.md"
  run_check "$INV" "$work/docs-empty-verdict"
  expect_fail "a record whose verdict cell is empty is rejected" "does not map E-0"

  # a stray line naming the task is not the task table's row
  mkdir -p "$work/docs-stray-line"
  grep -v '^| E-5 ' "$DOC" >"$work/docs-stray-line/upstream-coverage.md"
  printf '| E-5 | preserved |\n' >>"$work/docs-stray-line/upstream-coverage.md"
  run_check "$INV" "$work/docs-stray-line"
  expect_fail "a stray line naming a task does not satisfy the mapping" "does not map E-5"

  # a stray line of the task table's own shape, outside the table, does not
  # satisfy it either
  mkdir -p "$work/docs-stray-same-shape"
  grep -v '^| E-5 ' "$DOC" >"$work/docs-stray-same-shape/upstream-coverage.md"
  printf '| E-5 | some scope | preserved | some evidence |\n' >>"$work/docs-stray-same-shape/upstream-coverage.md"
  run_check "$INV" "$work/docs-stray-same-shape"
  expect_fail "a same-shape stray line does not satisfy the mapping" "does not map E-5"

  # the mapping is bound to the record's task table by identity: a record
  # whose task table has no rows at all, carrying an earlier Verdict-headed
  # table with the fifteen mappings, is rejected — the mappings are not
  # read out of a table that is not the task table
  mkdir -p "$work/docs-empty-task-table"
  task_table="$(awk '/^\| Old task \|/{f=1} f{print} /^\| E-14 /{f=0}' "$DOC")"
  {
    printf '%s\n\n' "$task_table"
    grep -v '^| E-' "$DOC"
  } >"$work/docs-empty-task-table/upstream-coverage.md"
  run_check "$INV" "$work/docs-empty-task-table"
  expect_fail "a record whose task table has no rows is rejected" "ambiguous"

  # two tables that both hold E-n ids are ambiguous, and the gate says so
  # instead of resolving silently to the first
  mkdir -p "$work/docs-two-task-tables"
  {
    printf '| Old task | Scope today | Verdict | Evidence |\n'
    printf '| --- | --- | --- | --- |\n'
    printf '| E-0 substituted row | substituted scope | preserved | substituted evidence |\n\n'
    cat "$DOC"
  } >"$work/docs-two-task-tables/upstream-coverage.md"
  run_check "$INV" "$work/docs-two-task-tables"
  expect_fail "two tables holding task ids are rejected as ambiguous" "ambiguous"

  # a renamed verdict column is a different problem from a missing row, and
  # the message must say which one it is
  mkdir -p "$work/docs-renamed-header"
  sed 's/^| Old task | Scope today | Verdict | Evidence |$/| Old task | Scope today | Disposition | Evidence |/' \
    "$DOC" >"$work/docs-renamed-header/upstream-coverage.md"
  run_check "$INV" "$work/docs-renamed-header"
  expect_fail "a renamed verdict column is rejected" "names no Verdict column"

  # the record must not overstate the re-pin: while the lab's own
  # documented pin rows still name the old tag, the record names them
  if grep -q 'v10\.2\.1' README.md 2>/dev/null; then
    if grep -E 'README\.md.*v10\.2\.1' "$DOC" >/dev/null 2>&1; then
      ok "the coverage record names the documented pin rows that still name the old tag"
    else
      bad "the coverage record names the documented pin rows that still name the old tag"
    fi
  else
    ok "the lab's documented pin rows name the pinned commit (nothing to record)"
  fi
fi

# --- the reported gaps match the assets on disk -----------------------------

run_check "$INV" docs
expected_eval_gaps="$(while IFS= read -r s; do
  [ -f "behavior/evals/$s/evals.json" ] || printf '%s\n' "$s"
done < <(jq -r '.skills[]' "$INV") | sort)"
reported_eval_gaps="$(printf '%s\n' "$check_out" | sed -n 's/^check: gap: no evals.json for //p' | sort)"
if [ "$expected_eval_gaps" = "$reported_eval_gaps" ]; then
  ok "the gate reports exactly the skills without an eval definition"
else
  bad "the gate reports exactly the skills without an eval definition"
fi

expected_adapter_gaps="$(while IFS= read -r h; do
  [ -f "harnesses/$h.sh" ] || printf '%s\n' "$h"
done < <(jq -r '.harnesses[]' "$INV") | sort)"
reported_adapter_gaps="$(printf '%s\n' "$check_out" | sed -n 's/^check: gap: no lab adapter for //p' | sort)"
if [ "$expected_adapter_gaps" = "$reported_adapter_gaps" ]; then
  ok "the gate reports exactly the harnesses without a lab adapter"
else
  bad "the gate reports exactly the harnesses without a lab adapter"
fi

expected_desc_gaps="$(while IFS= read -r s; do
  [ -f "descriptions/$s.json" ] || printf '%s\n' "$s"
done < <(jq -r '.skills[]' "$INV") | sort)"
reported_desc_gaps="$(printf '%s\n' "$check_out" | sed -n 's/^check: gap: no description set for //p' | sort)"
if [ "$expected_desc_gaps" = "$reported_desc_gaps" ]; then
  ok "the gate reports exactly the skills without a description set"
else
  bad "the gate reports exactly the skills without a description set"
fi

# The printed counters are the signal V3-CORPORA reads when it re-arms the
# list: each must equal the length of the list it summarises. That re-arm is
# the successor task's obligation, on the plan's own clause that lets the
# gaps be recorded first ("Initial coverage may record missing assets;
# V3-CORPORA closes them", 01-inventory.md) and its transfer of bin/check to
# V3-CORPORA (04-corpora.md).
counters_of() { # $1 gate output — the three numbers of the coverage line
  printf '%s\n' "$1" \
    | sed -n 's/^check: coverage checked: \([0-9][0-9]*\) skills without an eval definition, \([0-9][0-9]*\) without a description set, \([0-9][0-9]*\) without a lab adapter.*/\1 \2 \3/p'
}
list_length() { # $1 list — how many entries it has
  printf '%s\n' "$1" | grep -c .
}
if [ "$(counters_of "$check_out")" = \
    "$(list_length "$reported_eval_gaps") $(list_length "$reported_desc_gaps") $(list_length "$reported_adapter_gaps")" ]; then
  ok "the coverage counters equal the reported lists' lengths"
else
  bad "the coverage counters equal the reported lists' lengths (counters '$(counters_of "$check_out")')"
fi

# the coverage line is printed even when there is nothing to report: an
# empty result is an explicit zero, not the absence of a scan
zero_inv="$work/zero-gap-inventory.json"
jq '.skills = ["common/yagni"] | .harnesses = ["opencode"]' "$INV" >"$zero_inv"
run_check "$zero_inv" docs
if printf '%s\n' "$check_out" \
    | grep -q "coverage checked: 0 skills without an eval definition, 0 without a description set, 0 without a lab adapter"; then
  ok "the gate says so when there are no coverage gaps"
else
  bad "the gate says so when there are no coverage gaps"
fi
if [ "$(counters_of "$check_out")" = "0 0 0" ]; then
  ok "the zero-gap run's counters are zero"
else
  bad "the zero-gap run's counters are zero (counters '$(counters_of "$check_out")')"
fi

# a scan that cannot read the inventory must fail the gate: a counter that
# reads zero because nothing was scanned is a measurement that never
# happened, and it must not be printed as one
mkdir -p "$work/fake-bin"
cat >"$work/fake-bin/jq" <<'FAKEJQ'
#!/usr/bin/env bash
# a jq that cannot read the inventory's member lists
for a in "$@"; do
  if [ "$a" = ".skills[]" ] || [ "$a" = ".harnesses[]" ]; then
    echo "jq: cannot read the member lists" >&2
    exit 4
  fi
done
exec "$REAL_JQ" "$@"
FAKEJQ
chmod +x "$work/fake-bin/jq"
real_jq="$(command -v jq)"
check_out="$(PATH="$work/fake-bin:$PATH" REAL_JQ="$real_jq" bash bin/check --inventory 2>&1)" \
  && check_rc=0 || check_rc=$?
expect_fail "a coverage scan that cannot read the inventory fails" "cannot read the skill list from"
if printf '%s\n' "$check_out" | grep -q "coverage checked:"; then
  bad "a failed scan printed a coverage count"
else
  ok "a failed scan printed no coverage count"
fi

# --- the inventory and the coverage record agree ----------------------------
#
# The record is the one statement in the repository that is independent of
# the inventory, so it is what the inventory's membership is checked
# against. The counts come from the record, never from a literal here.

if [ -f "$DOC" ]; then
  record_skills="$(record_field 'Canonical skills')"
  record_harnesses="$(record_field 'Upstream harnesses')"
  inventory_skills="$(jq '.skills | length' "$INV")"
  inventory_harnesses="$(jq '.harnesses | length' "$INV")"
  if [ "$record_skills" = "$inventory_skills" ] && [ "$record_harnesses" = "$inventory_harnesses" ]; then
    ok "the inventory's counts equal the counts the coverage record states"
  else
    bad "the inventory's counts equal the counts the coverage record states (record $record_skills/$record_harnesses, inventory $inventory_skills/$inventory_harnesses)"
  fi

  record_eval_list="$(record_bullets 'Skills with no eval definition' | sort)"
  record_adapter_list="$(record_bullets 'Harnesses with no lab adapter' | sort)"
  record_eval_count="$(record_heading_count 'Skills with no eval definition')"
  record_desc_count="$(record_heading_count 'Skills with no description set')"
  record_adapter_count="$(record_heading_count 'Harnesses with no lab adapter')"

  if [ "$record_eval_list" = "$reported_eval_gaps" ]; then
    ok "the gate's eval-definition gaps equal the record's list"
  else
    bad "the gate's eval-definition gaps equal the record's list"
  fi
  # the record says the description gaps are the same skills
  if [ "$record_eval_list" = "$reported_desc_gaps" ]; then
    ok "the gate's description-set gaps equal the record's list"
  else
    bad "the gate's description-set gaps equal the record's list"
  fi
  if [ "$record_adapter_list" = "$reported_adapter_gaps" ]; then
    ok "the gate's adapter gaps equal the record's list"
  else
    bad "the gate's adapter gaps equal the record's list"
  fi
  if [ "$record_eval_count" = "$record_desc_count" ] \
      && [ "$(printf '%s\n' "$record_eval_list" | grep -c .)" = "$record_eval_count" ] \
      && [ "$(printf '%s\n' "$record_adapter_list" | grep -c .)" = "$record_adapter_count" ]; then
    ok "the record's own counts match the lists it enumerates"
  else
    bad "the record's own counts match the lists it enumerates"
  fi
fi

# --- no skill is excluded from the coverage scan ----------------------------
#
# The guard reads the gate's code, not its prose: a comment that names a
# skill path is not an exclusion, and only an exclusion may name one.

skill_paths_named_in() { # $1 file — the inventory skill paths it names outside a comment
  local file="$1" sk found="" code
  code="$(sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$file")"
  while IFS= read -r sk; do
    if printf '%s\n' "$code" | grep -qF -- "$sk"; then found="$found $sk"; fi
  done < <(jq -r '.skills[]' "$INV")
  printf '%s' "$found"
}

exempt_paths="$(skill_paths_named_in bin/check)"
if [ -z "$exempt_paths" ]; then
  ok "bin/check names no inventory skill path (no skill is excluded from the coverage scan)"
else
  bad "bin/check names an inventory skill path outside a comment:$exempt_paths"
fi

# a comment naming a skill path is not an exclusion
cp bin/check "$work/check-with-comment"
printf '# the implementation/subagent-driven-development scenario is authored by E-12\n' \
  >>"$work/check-with-comment"
if [ -z "$(skill_paths_named_in "$work/check-with-comment")" ]; then
  ok "a comment naming a skill path is not an exclusion"
else
  bad "a comment naming a skill path is not an exclusion"
fi

# --- the gate never reaches the network -------------------------------------
#
# The default CI gate validates the committed inventory offline, so a
# network command in the gate would make that gate depend on the network.
# The gate's own file is read and searched for one. Comments are stripped
# first: a comment naming a command is not a call. The pattern matches the
# command names in a command position — at the start of a line, after
# whitespace, after a shell separator, or inside a command substitution —
# so the pinned repository URL the gate legitimately holds as a string is
# not matched, and neither is a word that merely ends in a command name.

gate_code="$(sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' bin/check)"
if printf '%s\n' "$gate_code" | grep -qE \
    '(^|[[:space:]]|[;&|(]|\$\()(curl|wget|git[[:space:]]+(fetch|ls-remote|clone|pull|remote))([^[:alnum:]_-]|$)'; then
  bad "the gate holds no network command"
else
  ok "the gate holds no network command"
fi

# --- the shape predicates reject a malformed inventory ----------------------

if mutate '.skills = []' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "an inventory with no skills is rejected" "needs a non-empty skills array"
fi
if mutate '.harnesses = []' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "an inventory with no harnesses is rejected" "needs a non-empty harnesses array"
fi
if mutate '.harnesses[0] = "tests/harnesses/x.sh"' "$work/m.json"; then
  run_check "$work/m.json" docs
  expect_fail "a harness row that is not a plain name is rejected" "harness rows must be plain names"
fi
mkdir -p "$work/not-a-tree"
run_check "$INV" docs --plugin "$work/not-a-tree"
expect_fail "a directory that is not a plugin tree is rejected" "has no skills/ or tests/harnesses/ directory"

# --- the coverage scan reads the same root the shape check reads ------------
#
# The gate has one descriptions root. A caller that moves it moves both:
# the E-5 query-set shape check, which decides whether a set is well
# formed, and the coverage scan, which reports what is missing.

mkdir -p "$work/empty-descriptions"
check_out="$(DESCRIPTIONS_ROOT="$work/empty-descriptions" bash bin/check --inventory 2>&1)" \
  && check_rc=0 || check_rc=$?
seam_gaps="$(printf '%s\n' "$check_out" | sed -n 's/^check: gap: no description set for //p' | grep -c .)"
if [ "$seam_gaps" -eq "$(jq '.skills | length' "$INV")" ]; then
  ok "the coverage scan follows the descriptions root seam"
else
  bad "the coverage scan follows the descriptions root seam ($seam_gaps of $(jq '.skills | length' "$INV") skills)"
fi

# The shape check is the other reader of that root. The set below is
# malformed — it holds positives and no negatives, so it is not a query
# set — and it lives only under the moved root. The default root holds no
# such set, so the gate can only reject it if the shape check reads the
# seam. The full gate is run, not the pinned-scope mode: the pinned-scope
# mode exits before the shape check.
seam_descriptions="$work/seam-descriptions"
mkdir -p "$seam_descriptions/common"
jq -n '[range(20) | {query: "a malformed query \(.)", should_trigger: true, split: "train"}]' \
  >"$seam_descriptions/common/yagni.json"
check_out="$(INVENTORY_PATH="$INV" DOCS_ROOT=docs DESCRIPTIONS_ROOT="$seam_descriptions" bash bin/check 2>&1)" \
  && check_rc=0 || check_rc=$?
expect_fail "the query-set shape check reads the descriptions root seam" "needs >= 10 negatives"

exit "$fails"
