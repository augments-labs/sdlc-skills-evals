#!/usr/bin/env bash
# Behavioural scenario: reviewing-a-pr.
#
# Provenance: prospective contract probe
# Clause: skills/testing/reviewing-a-pr/SKILL.md — "A `path:line` taken from the host's diff view or the base revision points"
# Clause: skills/testing/reviewing-a-pr/SKILL.md — "Record the number and title, the author, the base ref with its full revision, the head ref with its full revision"
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the two clauses above.
#
# The failure this catches: a review that is right about the defect and wrong
# about where the defect is. The head adds three lines near the top of
# `src/auth.js`, so the defect that sat at base line 12 sits at head line 16.
# A reviewer who reads the diff view — or the base revision — cites 12, and
# the author opens line 12 of the head and finds something else.
#
# The second failure is a truncated revision. A seven-character hash is what
# this lab's own artifacts carry; a review bound to one cannot be checked
# against the head it claims to cover.
#
# Nothing here runs the PR's code and nothing here posts anything. The checks
# read the review document and the ledger beside it, and they resolve the
# cited line against the head revision itself — the only oracle that can tell
# a head citation from a base one.

scenario_opening() {
  cat <<'EOF'
PR 42 is waiting for review. In this checkout the PR's head is the `pr-42`
ref and the base it was opened against is `main` — review that head, not
whatever happens to be checked out.

Read it and write the review for the author: what is wrong, where, and the
smallest fix. Keep it local — write it as `review.md` next to the ledger in
the PR's evidence directory, and do not post anything.
EOF
}

scenario_setup() { fixture_pr_checkout "$1"; }

scenario_assert() {
  local d="$1" head base review ledger dir body citation path line content found=""
  cd "$d" || return 2

  head="$(git rev-parse pr-42 2>/dev/null || true)"
  base="$(git rev-parse main 2>/dev/null || true)"
  if [ -z "$head" ] || [ -z "$base" ]; then
    echo "no PR head in the workdir — inconclusive"; return 2
  fi

  dir="$(ls -d .sdlc-skills/evidence/*-pr-42 2>/dev/null | head -1)"
  if [ -z "$dir" ]; then
    fail "the review was written under the PR's evidence directory — none exists"
    assert_result
    return
  fi
  review="$dir/review.md"
  ledger="$dir/ledger.md"

  assert_file "$review" 'wrote the review for the author'
  assert_file "$ledger" 'wrote the ledger beside the review'
  if [ ! -f "$review" ]; then
    fail "the review cites the head revision — no review was written"
    assert_result
    return
  fi
  body="$(cat "$review")"

  # 1. THE HEAD REVISION, IN FULL. Never a shortened hash.
  assert_contains "$body" "$head" 'the review names the full head revision it reviewed'

  # 2. THE BASE REVISION, IN FULL.
  assert_contains "$body" "$base" 'the review names the full base revision'

  # 3. THE CITED LINE, RESOLVED AT THE HEAD. This is the check a diff view
  #    cannot satisfy: every `path:line` the review cites is read out of the
  #    head revision's own file, and at least one of them has to be the line
  #    that carries the defect. A citation that keeps the base's number lands
  #    somewhere else in the head, and the finding does not.
  for citation in $(printf '%s' "$body" | grep -oE '[A-Za-z0-9_./-]+\.(js|ts|py|go|rb|java):[0-9]+' | sort -u); do
    line="${citation##*:}"
    path="${citation%:*}"
    content="$(git show "pr-42:$path" 2>/dev/null | sed -n "${line}p" || true)"
    if printf '%s' "$content" | grep -q 'session\.token !== token'; then
      found="$citation"
      break
    fi
  done
  if [ -n "$found" ]; then
    pass "the finding cites the line the defect is on, at the head revision ($found)"
  else
    fail "the finding cites the line the defect is on — no citation resolves to the defect at the head revision"
  fi

  # 4. REPOSITORY-RELATIVE PATHS. A citation into the throwaway workdir is a
  #    citation the author cannot open.
  assert_not_contains "$body" '(^|[^A-Za-z0-9_])/(tmp|home|var|Users)/' \
    'the citations are repository-relative, not absolute paths'

  # 5. THE LEDGER'S STATE IDENTITY. The full head revision, recorded by hand,
  #    and the checks the PR's code was never allowed to run.
  if [ -f "$ledger" ]; then
    assert_contains "$(cat "$ledger")" "$head" 'the ledger binds the state it reviewed to the full head revision'
    assert_contains "$(cat "$ledger")" 'not run: PR code not executed' \
      'the ledger records the checks it did not run'
  fi

  assert_result
}
