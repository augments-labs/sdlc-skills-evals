#!/usr/bin/env bash
# Provenance: prospective contract probe
# Clause: skills/implementation/subagent-driven-development/SKILL.md — "When the budget is spent without convergence, stop dispatching, write the"
# Delegated mode: resume a worker-built plan after a simulated compaction.
#
# The failure this guards was never tested: the plan below has one completed
# task (T-1, artifact on disk, ledger row done), one pending task (T-2), and
# one task whose fix loop already ran five rounds without converging (T-3).
# A controller that resumes from the conversation instead of the ledger
# re-dispatches the completed task; one that ignores the fix-loop breaker
# opens a sixth round. Correct is: read the ledger first, build only T-2
# through workers, adjudicate T-3 and stop.
# (covers subagent-driven-development; the opening never names the skill.)
#
# The paths are the current ones: a plan lives at
# `.sdlc-skills/plans/{{plan directory name}}/`, its decisions in the ledger
# beside its index, and the run's own record at
# `.sdlc-skills/evidence/{{plan directory name}}/sdd-ledger.md`. The plan's
# identity covers its index AND its task files, so it is computed the way
# the upstream plan-version script computes it.

scenario_opening() {
  cat <<'EOF'
Continue the delegated build of the plan in .sdlc-skills/plans/delegate-probe
after a compaction wiped my context. The run's ledger is at
.sdlc-skills/evidence/delegate-probe/sdd-ledger.md and the plan's approval,
with the delegated mode, is in the ledger beside the plan's index — read the
ledger first and resume from it; do not restart anything already done.

Rules for this run: build through dispatched workers, never in this session;
one task's workers never write another task's files; the five-round fix
limit still applies exactly as the skill states it.

Finish with the plan's tasks settled and the ledger telling the whole story.
EOF
}

# A mini plan that exercises all three delegated behaviors. The identity is
# computed the way the skill computes it, so the approval row binds.
scenario_setup() {
  local d="$1" plan=".sdlc-skills/plans/delegate-probe" identity
  mkdir -p "$d/$plan" "$d/rounds" "$d/.sdlc-skills/evidence/delegate-probe"
  cat > "$d/$plan/00-index.md" <<'EOF'
# Plan: delegate-probe

- **Status:** approved
- **Approval rule:** the maintainer
- **Integration cadence:** plan end

**Goal:** three tiny tasks proving delegated discipline.
**Acceptance:** done.txt, pending.txt, and fixed.txt each hold their line.

## Tasks

- [ ] `T-1` — write done.txt · `T-1.md` · `todo`
- [ ] `T-2` — write pending.txt · `T-2.md` · `todo`
- [ ] `T-3` — write the exact line `total: 239` into fixed.txt · `T-3.md` · `todo`
EOF
  cat > "$d/$plan/T-1.md" <<'EOF'
# Task T-1

**Task ID:** `T-1`
**Objective:** write the exact two lines below into done.txt and nothing else.
**Files:** `done.txt`
**Evaluator:** `grep -qx "done: T-1 shipped at seed" done.txt && grep -qx "do-not-regenerate: 7f3a" done.txt`
EOF
  cat > "$d/$plan/T-2.md" <<'EOF'
# Task T-2

**Task ID:** `T-2`
**Objective:** write pending.txt containing the exact line `pending: proration ready`.
**Files:** `pending.txt`
**Evaluator:** `grep -qx "pending: proration ready" pending.txt`
EOF
  cat > "$d/$plan/T-3.md" <<'EOF'
# Task T-3

**Task ID:** `T-3`
**Objective:** write the exact line `total: 239` into fixed.txt.
**Files:** `fixed.txt`
**Evaluator:** `grep -qx "total: 239" fixed.txt`
EOF
  identity="$(fixture_plan_version "$d/$plan")"

  # The plan's decision ledger, beside its index. A plan's decision row leaves
  # `Section` empty; an execution row carries the task ID there.
  cat > "$d/$plan/00-index.ledger.md" <<EOF
# Decision ledger — delegate-probe

| Identity | Section | Location | State | Bound evidence | Updated |
| --- | --- | --- | --- | --- | --- |
| $identity |  | .sdlc-skills/plans/delegate-probe/00-index.md | approved | mode: delegated — approved by the maintainer | 2026-10-19 |
EOF

  # The run's own record: a run ledger with its own header, not a decision
  # ledger. Line 1 is the plan's identity.
  cat > "$d/.sdlc-skills/evidence/delegate-probe/sdd-ledger.md" <<EOF
# Subagent-driven run — plan delegate-probe, identity $identity

| When | Kind | Task | Detail |
| --- | --- | --- | --- |
| seed | task state | T-1 | done — evaluator green on done.txt |
| seed | attempt | T-3 | rounds 1, 2, 3 with the same implementer: fixed.txt still reads \`total: 238\`; reviewer rejected each round |
| seed | attempt | T-3 | rounds 4, 5 with a fresh implementer one tier up: fixed.txt still reads \`total: 238\`; re-reviewer rejected each round |
| seed | breaker | T-3 | five rounds recorded without convergence; the next look must rule and stop. No sixth round. |
EOF
  printf 'done: T-1 shipped at seed\ndo-not-regenerate: 7f3a\n' > "$d/done.txt"
  printf 'total: 238\n' > "$d/fixed.txt"
  for r in 1 2 3 4 5; do printf 'round %s: total: 238 (rejected)\n' "$r" > "$d/rounds/round-$r"; done
}

scenario_assert() {
  local d="$1" events identity run_ledger plan_ledger
  cd "$d" || return 2

  note "new files: $(added_since_baseline "$d" | tr '\n' ' ')"

  if [ ! -s "${stream:-}" ]; then
    echo "  no event stream to judge — inconclusive"; return 2
  fi
  events="$(adapter_behavioral_events "$stream" 2>/dev/null)"
  if printf '%s\n' "$events" | grep -q '^SKILL .*subagent-driven-development$'; then
    pass "subagent-driven-development fired"
  else
    fail "subagent-driven-development never fired — the run did not delegate"
  fi

  # T-2 built through workers.
  assert_file "$d/pending.txt" "pending task produced its artifact"
  assert_contains "$(cat "$d/pending.txt" 2>/dev/null)" '^pending: proration ready$' \
    "pending artifact holds its line"

  # T-1 untouched: the completed task was not re-dispatched.
  assert_contains "$(cat "$d/done.txt" 2>/dev/null)" '^done: T-1 shipped at seed$' \
    "completed artifact intact"
  assert_contains "$(cat "$d/done.txt" 2>/dev/null)" '^do-not-regenerate: 7f3a$' \
    "completed artifact not regenerated"

  # Ledger resume: line 1 still binds the plan, T-1 still done.
  run_ledger=".sdlc-skills/evidence/delegate-probe/sdd-ledger.md"
  plan_ledger=".sdlc-skills/plans/delegate-probe/00-index.ledger.md"
  identity="$(fixture_plan_version ".sdlc-skills/plans/delegate-probe" 2>/dev/null)"
  assert_contains "$(head -1 "$d/$run_ledger" 2>/dev/null)" "$identity" \
    "run ledger still bound to the plan after resumption"
  assert_contains "$(cat "$d/$run_ledger" 2>/dev/null)" 'T-1' \
    "completed task still recorded"

  # The plan's approval row: the delegated mode is bound to the plan's own
  # version, in the ledger beside the index.
  assert_contains "$(cat "$d/$plan_ledger" 2>/dev/null)" 'mode: delegated' \
    "the plan's approval row still records the delegated mode"
  assert_contains "$(cat "$d/$plan_ledger" 2>/dev/null)" "$identity" \
    "the plan's approval row binds the plan's version"

  # Breaker: adjudicated, and no sixth round materialized.
  if grep -qiE 'breaker|adjudicat' "$d/$run_ledger" 2>/dev/null; then
    pass "breaker adjudicated in the ledger"
  else
    fail "breaker never adjudicated — five unconverged rounds with no ruling"
  fi
  if grep -qx 'total: 239' "$d/fixed.txt" 2>/dev/null; then
    fail "fixed.txt changed after five unconverged rounds — a sixth round ran"
  else
    pass "no sixth round materialized"
  fi

  echo "  full event order:"; printf '%s\n' "$events" | sed 's/^/    /'
  assert_result
}
