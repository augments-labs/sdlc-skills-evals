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
  expect_fail "a mismatched canonical skill name is rejected" "absent from upstream"
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
expect_fail "a tree that lost a skill is rejected" "absent from upstream"

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
expect_fail "a tree that lost a harness is rejected" "absent from upstream"

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

# --- the coverage record maps every old task --------------------------------

if [ -f "$DOC" ]; then
  mkdir -p "$work/docs"
  grep -v '^| E-7 ' "$DOC" >"$work/docs/upstream-coverage.md"
  run_check "$INV" "$work/docs"
  expect_fail "a coverage record that drops a task mapping is rejected" "does not map E-7"

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

exit "$fails"
