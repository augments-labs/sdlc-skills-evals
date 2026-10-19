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
| E-5 descriptions runner and query sets (build only) | the runner stands; the sets are rebuilt for all 46 skills | extended | `71ea67e`; ledger 2026-09-18 `E-5` |
| E-6 output-evals format, grading, benchmark, report | the format stands; the reporting is widened to cover paired comparisons honestly | extended | `6101a0b`; ledger 2026-09-18 `E-6` |
| E-7 an `evals.json` for every skill | the scope widens from 37 to 46 skills; the nine missing definitions are the open part | extended | `11d3378`, `2f54875`; ledger 2026-09-18 `E-7` |
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
commit. V3-CORPORA closes the two skill gaps, V3-HARNESSES the adapter gap.
The old evals-coverage gate became this reported list so the initial
coverage can be recorded without a red cell: the plan's own clause permits
it — "Initial coverage may record missing assets; V3-CORPORA closes them"
(`01-inventory.md`) — and transfers `bin/check` to V3-CORPORA
(`04-corpora.md`). Re-arming the list as a hard failure is therefore
V3-CORPORA's obligation when the last definition lands; no task contract
states it in those words, and this record does not claim one. The last gap
is a documentation row, so the gate does not print it.

### Skills with no eval definition (9)

- `analysis/working-from-a-ticket`
- `design/reviewing-plans`
- `implementation/adding-observability`
- `implementation/changing-a-live-schema`
- `implementation/rollout-controls`
- `maintenance/deprecating-an-api`
- `maintenance/diagnosing-a-session`
- `maintenance/large-scale-changes`
- `testing/reviewing-a-pr`

### Skills with no description set (9)

The same nine skills: each needs a query set as well as an output eval.

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

## Re-verifying this record

```bash
bash bin/check                            # the committed inventory, offline
bash bin/check --plugin <upstream tree>   # drift against a tree, and the gaps
bash lib/tests/inventory.sh               # the mutations that prove the gate bites
```

The gate never fetches upstream. Membership is knowable only against a tree,
so a tree is supplied explicitly; everything else — the pin, the canonical
form, the uniqueness, the coverage record — is checked offline from the
committed files.
