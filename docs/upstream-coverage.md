# Upstream coverage — the pinned v11 scope and the work already done

This record answers two questions for whoever picks the lab up next.

1. **What has to be covered?** The pinned upstream: 46 canonical skills and
   11 harnesses, at one commit. `config/upstream-inventory.json` holds the
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
| Commit | `638040d407eae2834414968478792be99b3ff0cf` — a commit, not a mutable version tag |
| Package version | `11.0.0` |
| Canonical skills | 46, at `skills/<phase>/<name>/SKILL.md` |
| Upstream harnesses | 11, at `tests/harnesses/<name>.sh` |

The packaged mirror under `plugins/sdlc-skills/skills/` carries the same 46
skills in a flat layout. It is a distribution artifact, never a second
canonical copy: the inventory and the drift check count `skills/` only.

## What the earlier plan built

Verdicts: **preserved** — the scope stands as it was; **extended** — the
scope is carried forward and widened; **removed** — the successor drops the
obligation. `bin/check` fails when a task in this table has no verdict.

| Old task | Scope today | Verdict | Evidence |
| --- | --- | --- | --- |
| E-0 re-pin to v10.2.1, four renames | the committed inventory names the v11 commit, and the four renames stay applied; the lab's own documented pin rows still name the old tag (the gaps below) | extended | `f59d623`; ledger 2026-09-18 `E-0` |
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
commit. The two skill gaps are closed: every skill in the pin carries a
description set and an output-eval definition. The old evals-coverage gate
was a reported gap list so the initial coverage could be recorded without a
red cell — the plan's own clause permits it ("Initial coverage may record
missing assets; V3-CORPORA closes them", `01-inventory.md`) — and the last
definition has now landed, so the list is a **failure** again: a missing
asset fails the gate, and the lists are printed before it stops so a reader
sees what is missing. V3-CORPORA closed the two skill gaps and V3-HARNESSES
the adapter gap.

### Skills with no eval definition (0)

None. Every skill in the pin carries an output-eval definition with its own
fixture tree; the corpus audit below is the row per skill.

### Skills with no description set (0)

None. Every skill in the pin carries a description set of at least twenty
balanced queries with fixed `train`/`validation` splits and near-miss
negatives.

### Harnesses with no lab adapter (0)

None. The lab carries an adapter for every harness the pinned upstream names:
`antigravity`, `claude-code`, `codex`, `cursor`, `devin`, `grok`, `hermes`,
`kimi-code`, `muse`, `opencode` and `pi`. An adapter is a launcher and its
contract test; whether the CLI runs on a given machine is a separate, later
question.

### Documented pin rows that still name the v10.2.1 tag (2)

The committed inventory names the v11 commit. These two rows of the lab's own
documentation still name the old tag, so the re-pin is not yet everywhere.

- `README.md:39` — the `bin/campaign new sdd-opencode --plugin v10.2.1` example still names the tag. `README.md` is V3-DOCS's file.
- `README.md:73` — the `SDLC_SKILLS_PIN` row of the environment-variable table still names the `v10.2.1` tag. The variable is read by no shell file, so this is a documented pin rather than a live default; the run-time plugin ref is V3-RUNNERS's to pin.

## The corpus audit — one row per skill

Every skill in the pin carries two corpora: a description set of at least
twenty balanced queries with fixed `train`/`validation` splits and near-miss
negatives, and an output-eval definition of two or three cases with its own
fixture tree. A row is not a name: it links the upstream body the corpus was
written against, the positives, the near misses, the output case that bounds
the skill, and the inputs the corpus stages for it.

Two staged-input trees exist, and they are different things. The
**description-query tree** is what `bin/triggering` seeds each run with
(`fixtures/fixtures.sh`: `fixture_node_api` and `fixture_activation_paths`),
built from the tracked corpus root `fixtures/corpus/`, so a query that names
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

### The twelve changed sets — a changed corpus

Twelve of the retained query sets are not the sets that were there before
this task. Their queries changed, so **a rate measured against them before
this task is not comparable with one measured after it**, and the corpora are
a new corpus from here. Every entry that did not change kept its split, so
the measurement a split carries is unchanged for those entries.

| Set | What changed | Why |
| --- | --- | --- |
| `common/clarifying-intent` | five near misses added | the v11 body of `working-from-a-ticket` says the case it declines is `clarifying-intent`'s |
| `common/writing-skills` | three queries re-pointed | they named `skills/…` and `scripts/…` paths the staged tree does not hold; they now name the library's skills and validator in words |
| `common/using-sdlc-skills` | one query re-pointed | it named a project outside the run workdir |
| `common/viewing-artifacts` | one query re-pointed | the plan directory it named is now the current convention |
| `design/migration-strategy` | five near misses added | the v11 body of `changing-a-live-schema` says the case it declines is `migration-strategy`'s |
| `design/writing-plans` | one query re-pointed | the plan directory it named is now the current convention |
| `implementation/executing-plans` | six queries re-pointed | the plan directories they named are now the current convention |
| `implementation/subagent-driven-development` | three queries re-pointed | the plan directory and the run ledger they named are now the current convention |
| `maintenance/debugging` | five near misses added | the v11 body of `diagnosing-a-session` says the case it declines is `debugging`'s |
| `maintenance/post-mortem` | five near misses added | the v11 bodies of `diagnosing-a-session`, `adding-observability` and `rollout-controls` say the cases they decline are `post-mortem`'s |
| `maintenance/refactor-architecture` | five near misses added | the v11 body of `large-scale-changes` says the case it declines is `refactor-architecture`'s |
| `testing/requesting-code-review` | five near misses added | the v11 body of `requesting-code-review` names `reviewing-plans` as the skill that reviews a plan document |

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
| `analysis/working-from-a-ticket` | `skills/analysis/working-from-a-ticket/SKILL.md` | 10 | 10 | 3 — `ticket-unreadable` | `behavior/evals/analysis/working-from-a-ticket/files/` (11 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `docs` |
| `analysis/writing-specs` | `skills/analysis/writing-specs/SKILL.md` | 10 | 10 | 2 — `vague-edges` | `behavior/evals/analysis/writing-specs/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name `docs` |
| `common/clarifying-intent` | `skills/common/clarifying-intent/SKILL.md` | 10 | 15 | 2 — `praise-is-not-approval` | `behavior/evals/common/clarifying-intent/files/` (4 files: `README.md`, `package.json`, `src`); queries name `docs` |
| `common/dispatching-parallel-agents` | `skills/common/dispatching-parallel-agents/SKILL.md` | 10 | 10 | 2 — `coupled-writes` | `behavior/evals/common/dispatching-parallel-agents/files/` (8 files: `README.md`, `package.json`, `src`); queries name `src` |
| `common/handoff` | `skills/common/handoff/SKILL.md` | 10 | 10 | 2 — `finished-work` | `behavior/evals/common/handoff/files/` (10 files: `README.md`, `package.json`, `plans`, `src`); queries name no path |
| `common/mapping-the-codebase` | `skills/common/mapping-the-codebase/SKILL.md` | 10 | 10 | 2 — `already-mapped` | `behavior/evals/common/mapping-the-codebase/files/` (7 files: `README.md`, `package.json`, `src`); queries name `src` |
| `common/prototyping` | `skills/common/prototyping/SKILL.md` | 10 | 10 | 2 — `known-answer` | `behavior/evals/common/prototyping/files/` (4 files: `README.md`, `package.json`, `src`); queries name no path |
| `common/using-git-worktrees` | `skills/common/using-git-worktrees/SKILL.md` | 10 | 10 | 2 — `read-only` | `behavior/evals/common/using-git-worktrees/files/` (4 files: `README.md`, `package.json`, `src`); queries name `src` |
| `common/using-sdlc-skills` | `skills/common/using-sdlc-skills/SKILL.md` | 10 | 10 | 2 — `status-question` | `behavior/evals/common/using-sdlc-skills/files/` (5 files: `README.md`, `package.json`, `src`); queries name `src` |
| `common/viewing-artifacts` | `skills/common/viewing-artifacts/SKILL.md` | 10 | 10 | 2 — `write-spec` | `behavior/evals/common/viewing-artifacts/files/` (8 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `common/writing-skills` | `skills/common/writing-skills/SKILL.md` | 10 | 10 | 2 — `vague-skill` | `behavior/evals/common/writing-skills/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `common/yagni` | `skills/common/yagni/SKILL.md` | 10 | 10 | 2 — `cutting-correctness` | `behavior/evals/common/yagni/files/` (5 files: `README.md`, `package.json`, `src`); queries name `api`, `src` |
| `deployment/finishing-a-branch` | `skills/deployment/finishing-a-branch/SKILL.md` | 10 | 10 | 2 — `dirty-branch` | `behavior/evals/deployment/finishing-a-branch/files/` (4 files: `README.md`, `package.json`, `src`); queries name no path |
| `deployment/release-readiness` | `skills/deployment/release-readiness/SKILL.md` | 10 | 10 | 2 — `first-release` | `behavior/evals/deployment/release-readiness/files/` (7 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `design/architecture-decisions` | `skills/design/architecture-decisions/SKILL.md` | 10 | 10 | 2 — `reversible-trivia` | `behavior/evals/design/architecture-decisions/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `design/coding-standards` | `skills/design/coding-standards/SKILL.md` | 10 | 10 | 2 — `personal-style` | `behavior/evals/design/coding-standards/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `design/data-model` | `skills/design/data-model/SKILL.md` | 10 | 10 | 2 — `stateless-pricing` | `behavior/evals/design/data-model/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name no path |
| `design/migration-strategy` | `skills/design/migration-strategy/SKILL.md` | 10 | 15 | 2 — `bounded-rename` | `behavior/evals/design/migration-strategy/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `design/reviewing-plans` | `skills/design/reviewing-plans/SKILL.md` | 10 | 10 | 3 — `unwritten-plan` | `behavior/evals/design/reviewing-plans/files/` (9 files: `README.md`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `design/system-architecture` | `skills/design/system-architecture/SKILL.md` | 10 | 10 | 2 — `single-function` | `behavior/evals/design/system-architecture/files/` (6 files: `README.md`, `package.json`, `src`); queries name no path |
| `design/ui-ux-design` | `skills/design/ui-ux-design/SKILL.md` | 10 | 10 | 2 — `decided-copy` | `behavior/evals/design/ui-ux-design/files/` (4 files: `README.md`, `docs`, `package.json`, `src`); queries name `empty` |
| `design/writing-plans` | `skills/design/writing-plans/SKILL.md` | 10 | 10 | 2 — `ambiguous-intent` | `behavior/evals/design/writing-plans/files/` (8 files: `README.md`, `docs`, `package.json`, `plans`, `src`); queries name `.sdlc-skills`, `docs`, `src` |
| `implementation/adding-observability` | `skills/implementation/adding-observability/SKILL.md` | 10 | 10 | 3 — `no-facility` | `behavior/evals/implementation/adding-observability/files/` (8 files: `README.md`, `config`, `package.json`, `src`); queries name no path |
| `implementation/changing-a-live-schema` | `skills/implementation/changing-a-live-schema/SKILL.md` | 10 | 10 | 3 — `pre-release-store` | `behavior/evals/implementation/changing-a-live-schema/files/` (6 files: `README.md`, `package.json`, `src`); queries name no path |
| `implementation/executing-plans` | `skills/implementation/executing-plans/SKILL.md` | 13 | 13 | 2 — `unapproved-plan` | `behavior/evals/implementation/executing-plans/files/` (14 files: `README.md`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `implementation/rollout-controls` | `skills/implementation/rollout-controls/SKILL.md` | 10 | 10 | 3 — `declined-rollout` | `behavior/evals/implementation/rollout-controls/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `implementation/subagent-driven-development` | `skills/implementation/subagent-driven-development/SKILL.md` | 10 | 10 | 2 — `breaker-trips` | `behavior/evals/implementation/subagent-driven-development/files/` (10 files: `README.md`, `evidence`, `package.json`, `plans`, `src`); queries name `.sdlc-skills` |
| `implementation/test-driven-development` | `skills/implementation/test-driven-development/SKILL.md` | 10 | 10 | 2 — `config-tweak` | `behavior/evals/implementation/test-driven-development/files/` (4 files: `README.md`, `package.json`, `src`); queries name `api`, `config`, `src` |
| `maintenance/complexity-audit` | `skills/maintenance/complexity-audit/SKILL.md` | 10 | 10 | 2 — `simple-module` | `behavior/evals/maintenance/complexity-audit/files/` (6 files: `README.md`, `package.json`, `src`); queries name `src` |
| `maintenance/containing-an-incident` | `skills/maintenance/containing-an-incident/SKILL.md` | 10 | 10 | 2 — `yesterday-test-failure` | `behavior/evals/maintenance/containing-an-incident/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name `go` |
| `maintenance/debugging` | `skills/maintenance/debugging/SKILL.md` | 10 | 15 | 2 — `obvious-typo` | `behavior/evals/maintenance/debugging/files/` (6 files: `README.md`, `package.json`, `src`); queries name `api`, `src` |
| `maintenance/deprecating-an-api` | `skills/maintenance/deprecating-an-api/SKILL.md` | 10 | 10 | 3 — `internal-only` | `behavior/evals/maintenance/deprecating-an-api/files/` (7 files: `README.md`, `docs`, `package.json`, `src`); queries name `src` |
| `maintenance/diagnosing-a-session` | `skills/maintenance/diagnosing-a-session/SKILL.md` | 10 | 10 | 3 — `not-a-session` | `behavior/evals/maintenance/diagnosing-a-session/files/` (7 files: `.agent`, `README.md`, `package.json`, `src`); queries name `.agent`, `src` |
| `maintenance/large-scale-changes` | `skills/maintenance/large-scale-changes/SKILL.md` | 10 | 10 | 3 — `one-pr-fits` | `behavior/evals/maintenance/large-scale-changes/files/` (8 files: `CODEOWNERS`, `README.md`, `package.json`, `packages`, `src`); queries name `src` |
| `maintenance/post-mortem` | `skills/maintenance/post-mortem/SKILL.md` | 10 | 15 | 2 — `ordinary-bug` | `behavior/evals/maintenance/post-mortem/files/` (8 files: `README.md`, `config`, `ops`, `package.json`, `src`); queries name no path |
| `maintenance/refactor-architecture` | `skills/maintenance/refactor-architecture/SKILL.md` | 10 | 15 | 2 — `local-cleanup` | `behavior/evals/maintenance/refactor-architecture/files/` (7 files: `README.md`, `package.json`, `src`); queries name `src` |
| `planning/define-goals` | `skills/planning/define-goals/SKILL.md` | 10 | 10 | 2 — `solution-in-search` | `behavior/evals/planning/define-goals/files/` (3 files: `README.md`, `docs`, `package.json`); queries name `docs` |
| `planning/feasibility-check` | `skills/planning/feasibility-check/SKILL.md` | 10 | 10 | 2 — `unknown-unknowns` | `behavior/evals/planning/feasibility-check/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `planning/scoping` | `skills/planning/scoping/SKILL.md` | 10 | 10 | 2 — `midstream-growth` | `behavior/evals/planning/scoping/files/` (2 files: `README.md`, `package.json`); queries name no path |
| `testing/receiving-code-review` | `skills/testing/receiving-code-review/SKILL.md` | 10 | 10 | 2 — `no-review` | `behavior/evals/testing/receiving-code-review/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `testing/requesting-code-review` | `skills/testing/requesting-code-review/SKILL.md` | 10 | 15 | 2 — `midway-checkpoint` | `behavior/evals/testing/requesting-code-review/files/` (4 files: `README.md`, `package.json`, `src`); queries name `src` |
| `testing/reviewing-a-pr` | `skills/testing/reviewing-a-pr/SKILL.md` | 10 | 10 | 3 — `own-pr` | `behavior/evals/testing/reviewing-a-pr/files/` (8 files: `README.md`, `package.json`, `src`, `test`); queries name no path |
| `testing/security-audits` | `skills/testing/security-audits/SKILL.md` | 10 | 10 | 2 — `comment-only` | `behavior/evals/testing/security-audits/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `testing/verification-before-completion` | `skills/testing/verification-before-completion/SKILL.md` | 10 | 10 | 2 — `stale-evidence` | `behavior/evals/testing/verification-before-completion/files/` (3 files: `package.json`, `src`, `test`); queries name `src` |
| `testing/verification-strategy` | `skills/testing/verification-strategy/SKILL.md` | 10 | 10 | 2 — `single-feature` | `behavior/evals/testing/verification-strategy/files/` (5 files: `README.md`, `package.json`, `src`); queries name no path |
| `testing/visual-ui-verification` | `skills/testing/visual-ui-verification/SKILL.md` | 10 | 10 | 2 — `backend-only` | `behavior/evals/testing/visual-ui-verification/files/` (5 files: `README.md`, `docs`, `package.json`, `src`); queries name no path |

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
