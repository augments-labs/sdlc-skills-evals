#!/usr/bin/env bash
# Behavioural scenario: reviewing-plans.
#
# Provenance: prospective contract probe
# Clause: skills/design/reviewing-plans/SKILL.md — "Print the plan's version with the `plan-version.sh` script that"
# Clause: skills/design/reviewing-plans/SKILL.md — "A finding that cites no task ID, section, or `path:line`: record it as"
# Clause: skills/design/reviewing-plans/assets/plan-reviewer.md — "This review is void"
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the three clauses above.
#
# The failure this catches: a review of some version of the plan rather than
# the version under review. A plan's identity covers its index AND its task
# files, so a task file edited under an untouched index changes the version —
# and a reviewer who reads the index, or who copies the version the index
# declares, reviews something other than what will be approved.
#
# The second failure is an uncited finding: a reviewer who flags a gap in the
# plan without saying which task or which line, so nobody can act on it and
# the next review cannot check whether it was fixed.
#
# Nothing here edits the plan, and the last check proves it: a reviewer who
# corrects the plan destroys the version the findings describe, and the
# review is void.

scenario_opening() {
  cat <<'EOF'
The plan in `.sdlc-skills/plans/2026-10-19-tenant-rollout/` is written and
ready to be put to the platform lead. Before anyone approves it, I want an
independent review of it.

Review that plan as it stands and write the review where the plan's evidence
directory can hold it. Do not change the plan itself.
EOF
}

scenario_setup() { fixture_reviewable_plan "$1"; }

scenario_assert() {
  local d="$1" plan report version dir finding
  cd "$d" || return 2
  # The verdict cannot be reached without this tool. Absent, the scenario is
  # INCONCLUSIVE: never a green, never a red.
  command -v git >/dev/null 2>&1 || { echo "no git on PATH — inconclusive"; return 2; }

  plan=".sdlc-skills/plans/2026-10-19-tenant-rollout"
  if [ ! -d "$plan" ]; then
    echo "no plan in the workdir — inconclusive"; return 2
  fi

  # The plan's version, computed the way the plan-version script computes it:
  # the index with its task states normalized, then every task file in index
  # order. A version read out of the index is not this.
  version="$(fixture_plan_version "$plan")"

  dir=".sdlc-skills/evidence/2026-10-19-tenant-rollout"
  report="$(ls "$dir"/00-index.review-*.md 2>/dev/null | head -1)"
  if [ -z "$report" ]; then
    fail "the review is written to the plan's evidence directory — no review report is there"
    assert_result
    return
  fi
  pass "the review is written to the plan's evidence directory ($report)"
  local body; body="$(cat "$report")"

  # 1. THE VERSION UNDER REVIEW. The report has to state the version it read.
  if printf '%s' "$body" | grep -qE 'Plan version:[[:space:]]*`?'"$version"'`?'; then
    pass "the review states the plan version it read ($version)"
  else
    fail "the review states the plan version it read — it does not carry $version, which is the version this plan computes to"
  fi

  # 2. THE BOUND INPUT, AT THE IDENTITY THE INDEX NAMES.
  assert_contains "$body" 'spec-4c1a9de' 'the review binds the approved input at the identity the index names'

  # 3. EVERY FINDING IS CITED. A finding that cites no task ID, section, or
  #    `path:line` is not a finding, and cannot be given a recorded decision.
  local cited uncited=""
  while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    case "$finding" in
      *T-[0-9]*|*':[0-9]'*|*'path:'*) cited=1 ;;
      *) uncited="$uncited [$finding]" ;;
    esac
  done < <(printf '%s\n' "$body" | grep -E '^[-*][[:space:]]*Location:' | sed 's/^[-*][[:space:]]*Location:[[:space:]]*//')
  if [ -z "$cited" ]; then
    fail "every finding cites a task ID, a section, or a path:line — no finding carries a Location"
  elif [ -n "$uncited" ]; then
    fail "every finding cites a task ID, a section, or a path:line — uncited:$uncited"
  else
    pass "every finding cites a task ID, a section, or a path:line"
  fi

  # 4. THE REVIEW LENSES. The review covers each lens, and says what it read.
  local l
  for l in Traceability Correctness Decomposition Consistency Assurance Control Authorization; do
    if printf '%s' "$body" | grep -qi "$l"; then
      pass "the review covers the $l lens"
    else
      fail "the review covers the $l lens — it is not in the report"
    fi
  done

  # 5. THE PLAN IS UNTOUCHED. A reviewer who edits the plan voids the review:
  #    the version the findings describe no longer exists.
  local root touched
  root="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
  touched="$( { [ -n "$root" ] && git diff --name-only "$root" HEAD -- "$plan" 2>/dev/null
                git status --porcelain -uall -- "$plan" 2>/dev/null | awk '{print $NF}'; } | sort -u )"
  if [ -z "$touched" ]; then
    pass "the plan was not edited by the review"
  else
    fail "the plan was not edited by the review — changed: $(printf '%s' "$touched" | tr '\n' ' ')"
  fi

  assert_result
}
