# shellcheck shell=bash
# shellcheck disable=SC2154
# The review states the plan version it read. A plan's version covers its
# index AND its task files, so it is computed with the same rule the upstream
# plan-version script applies rather than read out of the index.
plan=".sdlc-skills/plans/2026-10-19-tenant-rollout"
version="$(fixture_plan_version "$plan")"
dir=".sdlc-skills/evidence/2026-10-19-tenant-rollout"
mkdir -p "$dir"
cat > "$dir/00-index.review-$version-1.md" <<REVIEW
- Plan version: $version
- Approved inputs: `.sdlc-skills/specs/2026-10-19-tenant-rollout.md` at \`spec-4c1a9de\`
- Reviewer role: correctness reviewer (a role that did not write this plan)
- Verdict: blockers
- Dispatch receipt: not dispatched — the harness had no dispatch action, so
  the review was carried out in this session and the receipt is left for the
  caller
- Report path: .sdlc-skills/evidence/2026-10-19-tenant-rollout/00-index.review-$version-1.md
- Dispositions: the finding below is a \`decision\` for the index's \`Approval rule\` owner

# Plan review — tenant rollout

## Coverage

| Lens | Task IDs and sections read | Result |
| --- | --- | --- |
| Traceability | T-001, T-002; Acceptance | R1 and R2 are traced to T-001 and T-002 |
| Correctness | T-001, T-002; Files | the files named exist |
| Decomposition | T-001, T-002 | both tasks are bounded and independently evaluable |
| Consistency | T-001, T-002 | each task consumes what the index says it consumes |
| Assurance | T-001, T-002; Evaluator | both evaluators are commands that can fail |
| Control | T-002; Objective | the rollout's stop condition is not executable |
| Authorization | index; Approval rule | the plan is not yet approved |

### The rollout cannot be stopped without a deploy, which R2 requires

- Severity: blocker: the plan as written causes incomplete work
- Location: T-002, Objective
- Source contract: the approved input R2 — the rollout can be stopped without
  a deploy
- Evidence: T-001 adds the flag to \`config/flags.json\`, and T-002 reads it
  on every request; nothing in the plan says the flag is read at request time
  rather than at build time
- Required correction: state in T-002's Objective that the switch is read at
  request time, and add the off-state test to its Evaluator

## Not examined

The migration contract and the assurance matrix; the route was not classified
as high-risk in the index.

## Next action

The index's \`Approval rule\` owner decides the finding; the plan's author
records the answer.
REVIEW
