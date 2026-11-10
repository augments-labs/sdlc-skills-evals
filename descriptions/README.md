# descriptions/

Measurements, not gates. Nothing here has a correct answer known in advance —
you get a number, compare it to the number the previous iteration got, and
exercise judgement. **A red sheet here is not a regression.** That is what
separates this directory from `bin/check` and `lib/tests/`, where red does
mean something broke.

What lives here is the input to the Agent Skills standard's
description-optimization loop: score a description against a set of queries,
revise it against the failures, score it again, and keep the iteration that
did best. `bin/triggering` scores one description; `bin/optimize-description`
runs the whole loop. The corpora are their input, not a test suite that
happens to be written in JSON.

## Layout

```
descriptions/
  <skill>.json              at least 20 balanced positive/near-miss queries
  holdout/<skill>.json      5-10 fresh queries, written after selection (see holdout/README.md)
```

The runner is self-contained: it opens a session per query repetition, points it
at a seeded project from `fixtures/fixtures.sh`, and reads which skills fired from
the CLI's own stream through `harnesses/<name>.sh`.

```bash
bin/triggering --harness opencode --skill yagni --dry-run
bin/triggering --harness opencode --skill yagni
bin/optimize-description --harness opencode --skill yagni --dry-run
bin/optimize-description --harness opencode --skill yagni
```

`--help` covers the flags, and `README.md` `## Running it yourself` walks the
loop end to end (including `--apply`). This file covers what the flags cannot
say.

## User-run only

Both tools are shipped working and priced, and **only the user starts a live
run**, from their own terminal, after its `--dry-run`. No agent working on
this repository launches one, and CI runs the offline suites only
(`CLAUDE.md`). Query sets are maintained (renamed with skills, completed for
new ones); the shape check below is what keeps them honest between runs.

## Anyone can run this, and it spends your own quota

**A 20-query set at the defaults is 60 CLI invocations** — each repeated 3 times —
billed to whatever account your harness CLI is logged into, and `--all` runs
every set. Nothing about it is free and nothing about it runs in CI.

Always price a selection with `--dry-run` first; it prints the exact call count
and calls nothing. Runtime varies with the harness, query, and stopping limit.

## A trigger rate is not a pass mark

The standard describes three roles for query data:

1. **train** — the failures you are allowed to revise against.
2. **validation** — the split that *selects* which iteration you keep.
3. **a fresh held-out set, written after selection** — the only one the standard
   calls a test.

Roles 1 and 2 live in `descriptions/<skill>.json`. Role 3 is
`descriptions/holdout/<skill>.json`, and no such file exists until a real
selection has happened (`holdout/README.md`). Until then the honest limit has
a consequence people get wrong: because validation is what selection is performed on, repeated
selection burns it too. Tune against train and the holdout stays meaningful for
a while; tune against validation and you have overfitted away the only thing
that was telling you the truth. Either way, **neither split is a held-out
result**, so no number produced here is evidence that a description generalises
to openings nobody wrote down.

What the numbers are good for is comparison between two iterations of the same
description, measured the same way. That is genuinely useful and it is all they
are.

Practical consequences:

- Revise on **train** failures only — `bin/optimize-description` shows its
  reviser nothing else.
- Keep the iteration with the best **validation** rate, which is very often not
  the last one you tried — `bin/optimize-description` writes that one to
  `best-description.txt`. When no iteration has a validation rate (every
  validation run inconclusive), it selects nothing, records the outcome as
  `indeterminate`, and exits 2.
- Report the real numbers, including inconclusive and failing ones, and say how
  many runs produced them.

## The query sets

Drop a JSON array at `descriptions/<skill>.json`, named for the skill's
directory under the pinned plugin's `skills/`. The filename is the
contract — no registration, no code change. Each entry needs `query`,
`should_trigger`, and `split`; every negative also needs `expect`, naming the
expected neighbouring activity (`"none"` if there is none). This field is
diagnostic; the scorer does not evaluate that activity.

**The shape of a set is enforced by `bin/check`** (override root:
`DESCRIPTIONS_ROOT`): at least ten positives and ten near-miss negatives
(holdout files: 5–10), no duplicates, every entry with `split` and boolean
`should_trigger`, every negative with a non-empty `expect` that names a skill
the pin holds or the activity it belongs to, a validation split between a
quarter and a half of the set with the same positive-to-negative proportion
as train, and no query shared between a set and its holdout. Ten of each is
twenty queries: a set that cannot decide anything is not worth the money it
costs to run. A main set may not carry a `holdout` entry — that role belongs
to the holdout file, which is written after the selection. Twenty
happy-path positives decide nothing either: they pass every eval they are
ever run through and prove nothing.

**The near-misses are the point.** A description firing on its own happy-path
opening proves nothing, because every description does that. The runner observes the subject anywhere in the bounded skill chain, including
a prerequisite or an on-demand read for model selection. Another skill owning
the opening does not make a valid negative if that workflow legitimately calls
the subject later. Write near-misses where the subject remains outside the
requested boundary; a natural stopping point can make that boundary explicit.
Do not tell the agent which skill to avoid. Keep general explanations alongside
real adjacent work; explanations alone make an easy, unrepresentative set.

Keep each query's `train` or `validation` assignment. Correcting an ambiguous
query changes the measurement: restart comparison on the revised set and
disclose the change; old rates are not comparable. Do not move validation
failures into training or call either split an untouched held-out test.

**Ground the query in the fixture whenever the verb presupposes what it names.**
Asking to *add* `src/utils/money.ts` works whether or not that path exists;
asking to *delete* or *refactor* it does not — the agent answers that there is
no such file and routes nowhere, which is indistinguishable in the report from a
description that failed to fire. A query like that scores the fixture, not the
description. `fixtures/fixtures.sh` says what actually exists.

## What this costs, before you run it

Each repetition is a paid CLI invocation; one invocation can make several model
requests and tool calls. For a 20-query set, three repetitions means 60
invocations, or 24 for an eight-query validation split. The exact all-library
count changes with the corpus: use `--dry-run`, not a historical total.

A description is revised one skill at a time. Run only the affected selection;
a full sweep is not a routine gate. `--jobs` runs repetitions concurrently. It
changes elapsed time and resource contention, not the planned invocation count.

Negatives dominate that clock. A positive stops the moment the expected skill
fires; a negative has nothing to wait for and runs to `--max-turns` or the
timeout, so the back half of a set costs multiples of the front half.

**Keep `--jobs` equal across runs you intend to compare.** Concurrency does not
change what is measured, but it can change whether a call completes, and a
timeout scores as "did not fire" rather than being dropped from the denominator.
A before/after pair split across concurrency levels is confounded. Retain
timeout and truncation counts separately: bounded non-observation is not proof
that the skill would never fire.

## The sibling loop, and why it is not here

Output behavior is a different question from activation, and it has its own
workflow: `bin/evaluate` runs a skill's `evals/<skill>/evals.json` with the
skill (`with_skill`) and without it (`without_skill`), or against an older
plugin tree (`old_skill`, `--baseline-plugin`). Installed arms expose the
whole library, so a sibling skill can fire in `with_skill`; a control arm
that loads any skill is `indeterminate`, not a baseline. A passing control
does not erase a reported failure or a source contradiction.

Freeze the eval files, assertions, skill sources, and harness before
comparing arms. Assertions are checked mechanically on produced files where
possible (`[check:`), and judged by you or a controlled rubric grader where
the claim needs judgment. Neither an exit code nor an agent's assurance alone
proves that the intended behavior was observed. `evals/README.md` and
`docs/authoring.md` own that workflow and its limits.

## Honest limits

Live runs cost tokens and are **not deterministic**: the same query fires and
does not fire across runs, and coverage is selective by design. So these are
user-run tools, never CI. A triggering result is committed only as the
summary a maintainer deliberately records (`bin/triggering --summary`, then
`bin/report --triggering`; `results/README.md` has the shape) — re-run
for current truth.

A single green run is weak evidence. Say how many runs you did and what the
spread was; the runner prints `(fired/valid)` beside every rate for exactly that
reason. A run the harness marks **inconclusive** is dropped from the
denominator rather than scored, because a provider that never answered is not
evidence about a description. An observed failure the harness cannot explain is
a finding, not a rerun.
