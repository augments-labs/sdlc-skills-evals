# Upstream coverage — the pinned v12 scope and the work already done

This record answers two questions for whoever picks the lab up next.

1. **What has to be covered?** The pinned upstream: the 48 canonical skills
   the inventory holds, of the 49 at the pin, and 11 harnesses, at one
   commit. `config/upstream-inventory.json` holds the
   pin; `bin/check` enforces it offline.
2. **What of the earlier plan is already built?** Every task of the
   predecessor plan, mapped to preserved, extended or removed scope, with
   the commit that proves it.

The predecessor plan's task list is entirely unchecked. Those boxes are not
evidence of absence: the decision ledger rows and the commits below are. The
campaigns that waited for a recorded go were never half-written code — they
were finished machinery waiting for a run that only the user starts. One
obligation, E-11, was blocked on a capability that was never built, so it
was never started at all; the deferred-campaigns section below says which is
which.

## The pin

| Field | Value |
| --- | --- |
| Repository | `https://github.com/augments-labs/sdlc-skills` |
| Commit | `c1e995a0371b11271b1d9a393e89fb2f345b2611` — a commit, not a mutable version tag |
| Package version | `12.0.0` |
| Canonical skills | 48 of the 49 at `skills/<phase>/<name>/SKILL.md`; the inventory holds the bare `<name>`. The 49th, `runtime-evidence`, is new in `12.0.0` and joins the inventory together with its eval set and query set, which the gate requires of every skill it holds |
| Upstream harnesses | 11, at `tests/harnesses/<name>.sh` |

The packaged mirror under `plugins/sdlc-skills/skills/` carries the same
skills as `skills/` in a flat layout. It is a distribution artifact, never a second
canonical copy: the inventory and the drift check count `skills/` only.
`bin/check --plugin` reads a skill as the basename of the directory that
holds its `SKILL.md`, so it accepts either layout, and it refuses a tree in
which two directories share a basename. A packaged mirror carries no
`tests/harnesses/`; against one, the check prints a notice that harness
membership was not compared rather than reporting the harnesses missing.

## What the earlier plan built

Verdicts: **preserved** — the scope stands as it was; **extended** — the
scope is carried forward and widened; **removed** — the successor drops the
obligation. `bin/check` fails when a task in this table has no verdict.

| Old task | Scope today | Verdict | Evidence |
| --- | --- | --- | --- |
| E-0 re-pin to v10.2.1, four renames | the committed inventory names the v11 commit, and the four renames stay applied; the lab's documented pin rows name it too (no gap below) | extended | `f59d623`; ledger 2026-09-18 `E-0` |
| E-1 repository skeleton, safety model, static CI | the same skeleton, and CI still runs shellcheck, `bin/check` and the offline tests | preserved | `f78a16a`; ledger 2026-09-18 `E-1` |
| E-2 shared seams in `lib/` (assertion verbs, verdicts, throwaway home, plugin pinning) | the seams stand; the run boundary and the report seams are widened around them | extended | `353485d`; ledger 2026-09-18 `E-2` |
| E-3 harness launchers, including the opencode behavioral adapter | four launchers stand; the seven missing adapters are added next | extended | `9dc9ca5`; ledger 2026-09-18 `E-3` |
| E-4 fixtures, behavior runner, scenarios, frozen manifests | the runner and the manifests stand; the scenarios are refreshed against current skill behavior | extended | `26a9ac9`; ledger 2026-09-18 `E-4` |
| E-5 descriptions runner and query sets (build only) | the runner stands; the sets are rebuilt for all 46 skills against the pinned v11 bodies, and twelve of the retained sets are a CHANGED corpus (the section below names them) | extended | `71ea67e`; ledger 2026-09-18 `E-5` |
| E-6 output-evals format, grading, benchmark, report | the format stands; the reporting is widened to cover paired comparisons honestly | extended | `6101a0b`; ledger 2026-09-18 `E-6` |
| E-7 an `evals.json` for every skill | the scope widened from 37 to 46 skills; every skill in the pin now carries a definition with its own fixture tree, and every case names a path its tree holds | extended | `11d3378`, `2f54875`; ledger 2026-09-18 `E-7` |
| E-8 campaign tooling and record layout | the tooling stands; the run boundary moves to the user | extended | `4be5e41`; ledger 2026-09-18 `E-8` |
| E-9 baseline record on opencode against v10.2.1 | the successor drops the campaign obligation; the record tooling it would have used stays | removed | predecessor plan, task list; no commit — it never ran |
| E-10 scenario hygiene authoring, with the run half deferred | the authoring is refreshed with the scenarios; the deferred run half leaves the scope | extended | `22c7919`; ledger 2026-09-18 `E-10` |
| E-11 tier measurement, blocked until the opencode adapter binds tiers | the successor drops the obligation, and no tier floor is claimed | removed | predecessor plan, task list; no commit — it never ran |
| E-12 the SDD scenario, evals and query set, plus the one live run | the assets and the recorded green run stand; the live run is no longer an acceptance requirement | preserved | `8c3458e`, `c6c8ec9`; `results/2026-09-18-sdd-opencode/`; ledger 2026-09-18 `E-12` |
| E-13 per-plugin-release records | the successor drops the obligation, and the lab is still never versioned or released | removed | predecessor plan, task list; no commit — it never ran |
| E-14 authoring, triage and harness guides, and the records-not-code rule | the guides stand; a user runbook and an offline acceptance record are added | extended | `973acde`; ledger 2026-09-18 `E-14` |

Rows E-2, E-4, E-8 and E-10 describe the lab before the behavior runner, its
scenarios and manifests, `bin/campaign`, `lib/verdict.sh` and
`lib/prelude.sh` were retired by the agentskills.io alignment, and "46
skills" in E-5 and E-7 is that pin's count; the inventory holds 48. E-0's
"the committed inventory names the v11 commit", E-5's "the pinned v11
bodies" and E-7's "every skill in the pin now carries a definition" were
true of the pin of that time, as is each "the v11 body of" cell of the
corpus audit; the pin is now `12.0.0`, the inventory names its commit, and
one skill at it has no definition yet (the gaps section below). The rows
stay as written: they are provenance.

Work after the tasks themselves: the independent review fixes (`5b15240`),
the pull-request feedback round (`2d15beb`) and the merge of the whole lab
(`054080b`, the base this record starts from).

## Deferred campaigns are not unfinished code

Four campaign obligations never ran: the baseline record (E-9), the scenario
hygiene run (the run half of E-10), the tier table (E-11) and the
per-plugin-release records (E-13). Three of them were complete machinery
waiting for a recorded go to start a live run: E-9 and E-13 had `bin/campaign`
to run, which exists from E-8, and the run half of E-10 had the runner and
the authored scenarios. E-13 also waited on E-9's baseline record, which
never existed.

E-11 is the one that was never started. It was blocked on a missing
capability, not on a run: the opencode adapter never bound tiers to models
(`harnesses/opencode.sh` still declares `tier-settable=documentation`), so
no tier floor could be set from this lab. Its build half was never written
either — `behavior/scenarios/tier-probe.sh`, its check manifest, its suite
row and the tier binding — and the predecessor plan's `11-tier-measurement.md`
named those files as that task's build half. A deferred campaign and
unfinished code are different things, and E-11 is the second; the table
above still records it as removed, and no tier floor is claimed from it.

The successor drops all four obligations; what it keeps is the run boundary,
now in the user's hands.

## Gaps against the pin

`bin/check` prints the three asset lists on every run that reaches the
pinned-scope section — the last section of the full gate — so a run that
fails earlier prints none of them; the lists below are their state at this
commit. The lists are computed from the inventory, and for it the two skill
gaps are closed: every skill the inventory holds carries a description set
and an output-eval definition. The 49th skill at the pin,
`runtime-evidence`, is not in the inventory yet and has neither; no list
below names it. The old evals-coverage gate
was a reported gap list so the initial coverage could be recorded without a
red cell — the plan's own clause permits it ("Initial coverage may record
missing assets; V3-CORPORA closes them", `01-inventory.md`) — and the last
definition has now landed, so the list is a **failure** again: a missing
asset fails the gate, and the lists are printed before it stops so a reader
sees what is missing. V3-CORPORA closed the two skill gaps and V3-HARNESSES
the adapter gap.

### Skills with no eval definition (0)

None. Every skill the inventory holds carries an output-eval definition
with its own fixture tree; the corpus audit below is the row per skill.

### Skills with no description set (0)

None. Every skill the inventory holds carries a description set of at least
twenty balanced queries with fixed `train`/`validation` splits and near-miss
negatives.

### Harnesses with no lab adapter (0)

None. The lab carries an adapter for every harness the pinned upstream names:
`antigravity`, `claude-code`, `codex`, `cursor`, `devin`, `grok`, `hermes`,
`kimi-code`, `muse`, `opencode` and `pi`. An adapter is a launcher and its
contract test; whether the CLI runs on a given machine is a separate, later
question.

### Documented pin rows that still name the v10.2.1 tag (0)

None.

### The frozen split assignment

A rate is only comparable with a rate measured against the same entries in
the same splits, so the per-entry split of every retained set is frozen
here and `bin/check` compares each set against it: an entry that moves
between `train` and `validation` fails the gate. The two sets the `v11.2.0`
pin added, `brainstorming` and `eliminating-corrections`, have no earlier
assignment and are not frozen. Sets are keyed by the bare skill name, the
way the corpus stores them at `descriptions/<skill>.json`.

The block below is the data the gate reads. `frozen_splits` maps a skill to
one letter per entry, in the set's order: `T` is `train`, `V` is
`validation`. `selections` names the selections that have happened; a holdout
file is accepted only when the selection it follows is named here, so a
holdout cannot simply be placed in the corpus before the selection step.

<!-- corpus-state:begin -->
```json
{
  "frozen_splits": {
    "adding-observability": "TTTTTTVVVVTTTTTTVVVV",
    "architecture-decisions": "TTTTTVVVTVTTTTTVVVTV",
    "changing-a-live-schema": "TTTTTTVVVVTTTTTTVVVV",
    "clarifying-intent": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "coding-standards": "TTTTTVVVTVTTTTTVVVTV",
    "complexity-audit": "TTTTTVVVTVTTTTTVVVTV",
    "containing-an-incident": "TTTTTTTTTTTTVVVVVVVV",
    "data-model": "TTTTTVVVTVTTTTTVVVTV",
    "debugging": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "define-goals": "TTTTTVVVTVTTTTTVVVTV",
    "deprecating-an-api": "TTTTTTVVVVTTTTTTVVVV",
    "diagnosing-a-session": "TTTTTTVVVVTTTTTTVVVV",
    "dispatching-parallel-agents": "TTTTTVVVTVTTTTTVVVTV",
    "executing-plans": "TTTTTVVVTVTVVTTTTTVVVTVTVV",
    "feasibility-check": "TTTTTVVVTVTTTTTVVVTV",
    "finishing-a-branch": "TTTTTVTVVVTTTTTVVVTV",
    "handoff": "TTTTTVVVTVTTTTTVVVTV",
    "large-scale-changes": "TTTTTTVVVVTTTTTTVVVV",
    "mapping-the-codebase": "TTTTTVVVTVTTTTTVVVTV",
    "migration-strategy": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "post-mortem": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "prototyping": "TTTTTVVVTVTTTTTVVVTV",
    "receiving-code-review": "TTTTTVVVTVTTTTTVVVTV",
    "refactor-architecture": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "release-readiness": "TTTTTVVVTVTTTTTVVVTV",
    "requesting-code-review": "TTTTTVVVTVTTTTTVVVTVTTTVV",
    "reviewing-a-pr": "TTTTTTVVVVTTTTTTVVVV",
    "reviewing-plans": "TTTTTTVVVVTTTTTTVVVV",
    "rollout-controls": "TTTTTTVVVVTTTTTTVVVV",
    "scoping": "TTTTTVVVTVTTTTTVVVTV",
    "security-audits": "TTTTTVVVTVTTTTTVVVTV",
    "subagent-driven-development": "TTTTTTTTTTTTVVVVVVVV",
    "system-architecture": "TTTTTVVVTVTTTTTVVVTV",
    "test-driven-development": "TTTTTVVVTVTTTTTVVVTV",
    "ui-ux-design": "TTTTTVVVTVTTTTTVVVTV",
    "using-git-worktrees": "TTTTTVVVTVTTTTTVVVTV",
    "using-sdlc-skills": "TTTTTTTTTTTTVVVVVVVV",
    "verification-before-completion": "TTTTTVVVTVTTTTTVVVTV",
    "verification-strategy": "TTTTTVVVTVTTTTTVVVTV",
    "viewing-artifacts": "TTTTTVVVVVTTTTTVVVVV",
    "visual-ui-verification": "TTTTTVVVTVTTTTTVVVTV",
    "working-from-a-ticket": "TTTTTTVVVVTTTTTTVVVV",
    "writing-plans": "TTTTTVVVTVTTTTTVVVTV",
    "writing-skills": "TTTTTVVVTVTTTTTVVVTV",
    "writing-specs": "TTTTTVVVTVTTTTTVVVTV",
    "yagni": "TTTTTVVVTVTTTTTVVVTV"
  },
  "new_sets": [
    "brainstorming",
    "eliminating-corrections"
  ],
  "selections": {}
}
```
<!-- corpus-state:end -->

## The corpus audit — one row per skill

Every skill the inventory holds carries two corpora: a description set of at
least twenty balanced queries with fixed `train`/`validation` splits and
near-miss negatives, and an output-eval definition of two or three cases
with its own fixture tree. A row is not a name: it links the upstream body the corpus was
written against, the positives, the near misses, the output case that bounds
the skill, and the inputs the corpus stages for it. `12.0.0` changed the
body of every one of the 48 skills, and no set has been re-checked against
the new bodies yet.

Two staged-input trees exist, and they are different things. The
**description-query tree** is what `bin/triggering` seeds each run with
(`fixtures/fixtures.sh`: `fixture_node_api` and `fixture_activation_paths`),
built from the tracked seed root `fixtures/seed/`, so a query that names
a path finds it real; the "queries name" column lists the roots the skill's
queries presuppose. The **output-eval tree** is the skill's own `files/`
directory, copied into the run workdir, so an output case is answerable from
the project it names. The output-eval tree alone does not make a description
query ready, and the description-query tree alone does not make an output
case answerable.

A plan sits at `.sdlc-skills/plans/{{YYYY-MM-DD}}-{{topic}}/` in the
description-query tree and at `plans/{{YYYY-MM-DD}}-{{topic}}/` in an
output-eval tree. The first is a throwaway workdir the runner builds; the
second is a directory the repository tracks, because the repository ignores
`.sdlc-skills/` — the lab's own plans, ledgers and run state stay local, so
a fixture under that name would be present in the working tree and absent
from the commit. One plan material serves both, and a plan's identity covers
its index and its task files, not its ledger, so the two copies keep the same
version.

A row that says "no path" is a skill whose queries presuppose nothing: they
design or ask rather than presuppose an artefact.

| `adding-observability` | `skills/implementation/adding-observability/SKILL.md` | 10 | 10 | 3 — `no-facility` | `evals/adding-observability/files/` (8 files: `README.md`, `config`, `package.json`, `src`); queries name no path |
| `architecture-decisions` | `skills/design/architecture-decisions/SKILL.md` | 10 | 10 | 2 — `reversible-trivia` | `evals/architecture-decisions/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `brainstorming` | `skills/planning/brainstorming/SKILL.md` | 10 | 10 | 3 — `approach-already-chosen` | `evals/brainstorming/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name `docs`, `src` |
| `changing-a-live-schema` | `skills/implementation/changing-a-live-schema/SKILL.md` | 10 | 10 | 3 — `pre-release-store` | `evals/changing-a-live-schema/files/` (6 files: `README.md`, `package.json`, `src`); queries name no path |
| `clarifying-intent` | `skills/common/clarifying-intent/SKILL.md` | 10 | 15 | 2 — `praise-is-not-approval` | `evals/clarifying-intent/files/` (4 files: `README.md`, `package.json`, `src`); queries name `docs` |
| `coding-standards` | `skills/design/coding-standards/SKILL.md` | 10 | 10 | 2 — `personal-style` | `evals/coding-standards/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `complexity-audit` | `skills/maintenance/complexity-audit/SKILL.md` | 10 | 10 | 2 — `simple-module` | `evals/complexity-audit/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `containing-an-incident` | `skills/maintenance/containing-an-incident/SKILL.md` | 10 | 10 | 2 — `yesterday-test-failure` | `evals/containing-an-incident/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name `go` |
| `data-model` | `skills/design/data-model/SKILL.md` | 10 | 10 | 2 — `stateless-pricing` | `evals/data-model/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name no path |
| `debugging` | `skills/maintenance/debugging/SKILL.md` | 10 | 15 | 2 — `obvious-typo` | `evals/debugging/files/` (6 files: `README.md`, `package.json`, `src`); queries name `api`, `src` |
| `define-goals` | `skills/planning/define-goals/SKILL.md` | 10 | 10 | 2 — `solution-in-search` | `evals/define-goals/files/` (3 files: `README.md`, `docs`, `package.json`); queries name `docs` |
| `deprecating-an-api` | `skills/maintenance/deprecating-an-api/SKILL.md` | 10 | 10 | 3 — `internal-only` | `evals/deprecating-an-api/files/` (7 files: `README.md`, `docs`, `package.json`, `src`); queries name `src` |
| `diagnosing-a-session` | `skills/maintenance/diagnosing-a-session/SKILL.md` | 10 | 10 | 3 — `not-a-session` | `evals/diagnosing-a-session/files/` (7 files: `.agent`, `README.md`, `package.json`, `src`); queries name `.agent`, `src` |
| `dispatching-parallel-agents` | `skills/common/dispatching-parallel-agents/SKILL.md` | 10 | 10 | 2 — `coupled-writes` | `evals/dispatching-parallel-agents/files/` (8 files: `README.md`, `package.json`, `src`); queries name `src` |
| `eliminating-corrections` | `skills/maintenance/eliminating-corrections/SKILL.md` | 10 | 10 | 3 — `one-off-demo-preference` | `evals/eliminating-corrections/files/` (8 files: `README.md`, `docs`, `package.json`, `src`, `test`); queries name `src` |
| `executing-plans` | `skills/implementation/executing-plans/SKILL.md` | 13 | 13 | 2 — `unapproved-plan` | `evals/executing-plans/files/` (14 files: `README.md`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `feasibility-check` | `skills/planning/feasibility-check/SKILL.md` | 10 | 10 | 2 — `unknown-unknowns` | `evals/feasibility-check/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `finishing-a-branch` | `skills/deployment/finishing-a-branch/SKILL.md` | 10 | 10 | 2 — `dirty-branch` | `evals/finishing-a-branch/files/` (4 files: `README.md`, `package.json`, `src`); queries name no path |
| `handoff` | `skills/common/handoff/SKILL.md` | 10 | 10 | 2 — `finished-work` | `evals/handoff/files/` (10 files: `README.md`, `package.json`, `plans`, `src`); queries name no path |
| `large-scale-changes` | `skills/maintenance/large-scale-changes/SKILL.md` | 10 | 10 | 3 — `one-pr-fits` | `evals/large-scale-changes/files/` (8 files: `CODEOWNERS`, `README.md`, `package.json`, `packages`, `src`); queries name `src` |
| `mapping-the-codebase` | `skills/common/mapping-the-codebase/SKILL.md` | 10 | 10 | 2 — `already-mapped` | `evals/mapping-the-codebase/files/` (7 files: `README.md`, `package.json`, `src`); queries name `src` |
| `migration-strategy` | `skills/design/migration-strategy/SKILL.md` | 10 | 15 | 2 — `bounded-rename` | `evals/migration-strategy/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `post-mortem` | `skills/maintenance/post-mortem/SKILL.md` | 10 | 15 | 2 — `ordinary-bug` | `evals/post-mortem/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `prototyping` | `skills/common/prototyping/SKILL.md` | 10 | 10 | 2 — `known-answer` | `evals/prototyping/files/` (4 files: `README.md`, `package.json`, `src`); queries name no path |
| `receiving-code-review` | `skills/testing/receiving-code-review/SKILL.md` | 10 | 10 | 2 — `no-review` | `evals/receiving-code-review/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `refactor-architecture` | `skills/maintenance/refactor-architecture/SKILL.md` | 10 | 15 | 2 — `local-cleanup` | `evals/refactor-architecture/files/` (7 files: `README.md`, `package.json`, `src`); queries name `src` |
| `release-readiness` | `skills/deployment/release-readiness/SKILL.md` | 10 | 10 | 2 — `first-release` | `evals/release-readiness/files/` (7 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `requesting-code-review` | `skills/testing/requesting-code-review/SKILL.md` | 10 | 15 | 2 — `midway-checkpoint` | `evals/requesting-code-review/files/` (4 files: `README.md`, `package.json`, `src`); queries name `src` |
| `reviewing-a-pr` | `skills/testing/reviewing-a-pr/SKILL.md` | 10 | 10 | 3 — `own-pr` | `evals/reviewing-a-pr/files/` (8 files: `README.md`, `package.json`, `src`, `test`); queries name no path |
| `reviewing-plans` | `skills/design/reviewing-plans/SKILL.md` | 10 | 10 | 3 — `unwritten-plan` | `evals/reviewing-plans/files/` (9 files: `README.md`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `rollout-controls` | `skills/implementation/rollout-controls/SKILL.md` | 10 | 10 | 3 — `declined-rollout` | `evals/rollout-controls/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `scoping` | `skills/planning/scoping/SKILL.md` | 10 | 10 | 2 — `midstream-growth` | `evals/scoping/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `security-audits` | `skills/testing/security-audits/SKILL.md` | 10 | 10 | 2 — `comment-only` | `evals/security-audits/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `subagent-driven-development` | `skills/implementation/subagent-driven-development/SKILL.md` | 10 | 10 | 2 — `breaker-trips` | `evals/subagent-driven-development/files/` (10 files: `README.md`, `evidence`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `system-architecture` | `skills/design/system-architecture/SKILL.md` | 10 | 10 | 2 — `single-function` | `evals/system-architecture/files/` (6 files: `README.md`, `package.json`, `src`); queries name no path |
| `test-driven-development` | `skills/implementation/test-driven-development/SKILL.md` | 10 | 10 | 2 — `config-tweak` | `evals/test-driven-development/files/` (4 files: `README.md`, `package.json`, `src`); queries name `api`, `config`, `src` |
| `ui-ux-design` | `skills/design/ui-ux-design/SKILL.md` | 10 | 10 | 2 — `decided-copy` | `evals/ui-ux-design/files/` (4 files: `README.md`, `docs`, `package.json`, `src`); queries name `empty` |
| `using-git-worktrees` | `skills/common/using-git-worktrees/SKILL.md` | 10 | 10 | 2 — `read-only` | `evals/using-git-worktrees/files/` (4 files: `README.md`, `package.json`, `src`); queries name `src` |
| `using-sdlc-skills` | `skills/common/using-sdlc-skills/SKILL.md` | 10 | 10 | 2 — `status-question` | `evals/using-sdlc-skills/files/` (5 files: `README.md`, `package.json`, `src`); queries name `src` |
| `verification-before-completion` | `skills/testing/verification-before-completion/SKILL.md` | 10 | 10 | 2 — `stale-evidence` | `evals/verification-before-completion/files/` (3 files: `package.json`, `src`, `test`); queries name `src` |
| `verification-strategy` | `skills/testing/verification-strategy/SKILL.md` | 10 | 10 | 2 — `single-feature` | `evals/verification-strategy/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `viewing-artifacts` | `skills/common/viewing-artifacts/SKILL.md` | 10 | 10 | 2 — `write-spec` | `evals/viewing-artifacts/files/` (8 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `visual-ui-verification` | `skills/testing/visual-ui-verification/SKILL.md` | 10 | 10 | 2 — `backend-only` | `evals/visual-ui-verification/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name no path |
| `working-from-a-ticket` | `skills/analysis/working-from-a-ticket/SKILL.md` | 10 | 10 | 3 — `ticket-unreadable` | `evals/working-from-a-ticket/files/` (11 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `docs` |
| `writing-plans` | `skills/design/writing-plans/SKILL.md` | 10 | 10 | 2 — `ambiguous-intent` | `evals/writing-plans/files/` (8 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `.sdlc-skills`, `docs`, `src` |
| `writing-skills` | `skills/common/writing-skills/SKILL.md` | 10 | 10 | 2 — `vague-skill` | `evals/writing-skills/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `writing-specs` | `skills/analysis/writing-specs/SKILL.md` | 10 | 10 | 2 — `vague-edges` | `evals/writing-specs/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name `docs` |
| `yagni` | `skills/common/yagni/SKILL.md` | 10 | 10 | 2 — `cutting-correctness` | `evals/yagni/files/` (5 files: `README.md`, `package.json`, `src`); queries name `api`, `src` |

### The twelve changed sets — a changed corpus

Twelve of the retained query sets are not the sets that were there before
this task. Their queries changed, so **a rate measured against them before
this task is not comparable with one measured after it**, and the corpora are
a new corpus from here. Every entry that did not change kept its split, so
the measurement a split carries is unchanged for those entries.

The counts below are recounted from the corpus against the task's base —
the revision before this task touched it, `691ea5e` — and they are
per-set, so a reader can check them rather than take them. Two shapes
occur:

- **grown** — the set gained near misses. Six sets.
- **re-pointed** — the set's queries were re-pointed at a path that exists
  (or at the run workdir), so the query is answerable where it is asked.
  Six sets.

No entry of any set changed its split, and no entry was removed.

| Set | Shape | Entries added | Entries re-pointed | Why |
| --- | --- | --- | --- | --- |
| `common/clarifying-intent` | grown | 5 | 0 | the v11 body of `working-from-a-ticket` says the case it declines is `clarifying-intent`'s |
| `common/using-sdlc-skills` | re-pointed | 0 | 1 | the query named a project outside the run workdir |
| `common/viewing-artifacts` | re-pointed | 0 | 1 | the plan directory it named is now the current convention |
| `common/writing-skills` | re-pointed | 0 | 3 | they named `skills/…` and `scripts/…` paths the staged tree does not hold; they now name the library's skills and validator in words |
| `design/migration-strategy` | grown | 5 | 0 | the v11 body of `changing-a-live-schema` says the case it declines is `migration-strategy`'s |
| `design/writing-plans` | re-pointed | 0 | 1 | the plan directory it named is now the current convention |
| `implementation/executing-plans` | re-pointed | 0 | 6 | the plan directories they named are now the current convention |
| `implementation/subagent-driven-development` | re-pointed | 0 | 3 | the plan directory and the run ledger they named are now the current convention |
| `maintenance/debugging` | grown | 5 | 0 | the v11 body of `diagnosing-a-session` says the case it declines is `debugging`'s |
| `maintenance/post-mortem` | grown | 5 | 0 | the v11 bodies of `diagnosing-a-session`, `adding-observability` and `rollout-controls` say the cases they decline are `post-mortem`'s |
| `maintenance/refactor-architecture` | grown | 5 | 0 | the v11 body of `large-scale-changes` says the case it declines is `refactor-architecture`'s |
| `testing/requesting-code-review` | grown | 5 | 0 | the v11 body of `requesting-code-review` names `reviewing-plans` as the skill that reviews a plan document |

The nine new sets — `analysis/working-from-a-ticket`,
`design/reviewing-plans`, `implementation/adding-observability`,
`implementation/changing-a-live-schema`, `implementation/rollout-controls`,
`maintenance/deprecating-an-api`, `maintenance/diagnosing-a-session`,
`maintenance/large-scale-changes` and `testing/reviewing-a-pr` — have no
earlier rate at all.

The remaining twenty-five sets are byte-identical to the ones the base held,
and a rate measured against them before this task is still comparable with
one measured after it.

| Skill | Upstream source | Positives | Near misses | Output cases | Staged inputs |
| --- | --- | --- | --- | --- | --- |

**Static readiness is not measured quality.** Nothing here is a trigger rate,
a pass rate or a score. It says the corpus is well formed, grounded and
complete; whether a description fires, and whether an output is good, is
measured by a live run, which the lab never starts on its own.

## Re-verifying this record

```bash
bash bin/check                            # the committed inventory, offline
bash bin/check --plugin <upstream tree>   # drift against a tree, and the gaps
bash lib/tests/inventory.sh               # the mutations that prove the gate bites
bash lib/tests/corpora.sh                 # the mutations that prove the corpora gate bites
```

The gate never fetches upstream. Membership is knowable only against a tree,
so a tree is supplied explicitly; everything else — the pin, the canonical
form, the uniqueness, the coverage record — is checked offline from the
committed files.
