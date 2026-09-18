# behavior/

One file per scenario under `behavior/scenarios/`, run by `bin/behavior`.
Each drives a real coding-agent CLI against a disposable project and then
reads **the artifact it produced** — not what it said about the artifact.

That is the whole reason these exist. A test that asks an agent to describe a
skill passes whenever the agent can paraphrase; only reading the output catches a
skill described correctly and *applied* wrongly — a spec that promises "all
criteria are automated tests" and ships none, or ships them marked `todo` so the
suite can never go red.

## The arms

GREEN loads the skills from `--plugin <path|ref>` (your change); RED loads
them from a throwaway worktree at `--base` in `SDLC_SKILLS_ROOT`, so the
before-arm stays reproducible AFTER the change is committed. This preserves
the baseline source, not deterministic model behavior. Compare the same
scenario under matching conditions.

`--arm none` loads no skills and observes the bare agent — and rejects
`--plugin` rather than ignoring it. A passing sample can narrow a failure
claim, but cannot erase an observed failure or establish that a skill is
useless. Keep current contract gaps distinct from sampled behavior. This
interface does not remove one skill from an otherwise identical library, so
it does not isolate that skill's contribution.

Each arm prints wall time and token usage when the adapter reports it. The
difference includes generated work and tool use, not just skill text. An
adapter without usage telemetry says so instead of printing zero. Report all
passes, failures, and inconclusive attempts.

## Verdicts

Verdicts are three-valued: `pass` (exit 0), `fail` (exit 1),
`indeterminate` (exit 2). A timeout, adapter error, provider refusal,
contaminated control, empty capture, unrunnable harness, a scenario whose
checks never ran, or a manifest mismatch is `indeterminate` — never a
false red or green, and never silent.

`scenario_assert` speaks the same three values: exit 0 the assertions
held, 1 they did not, 2 the scenario could not judge (no event stream, no
structured edit — the transferred scenarios already used `return 2` for
exactly this; the runner now scores what they meant).

## Writing one

A scenario is one file, `<name>.sh`, defining three required functions and
one optional continuation function:

```bash
scenario_opening          # the user's first message, verbatim
scenario_followups        # optional: fills followups=(...) for one resumed session
scenario_setup   <dir>    # seed the disposable project
scenario_assert  <dir>    # read what was built; exit code IS the verdict
```

Judge through the verbs in `lib/prelude.sh` (`pass`, `fail`,
`assert_contains`, `assert_not_contains`, `assert_file`) — never through
bare `echo`: only verbs count toward "a check ran", and only verbs are
covered by the frozen manifest. `note` reports, `assert_result` closes.
Display lines (`echo`) are fine for context and never decide anything.

Three optional variables narrow a run, and each is declared in the scenario
rather than inferred: `scenario_branch` names the branch the fixture is
seeded on (default `task/behavioral-probe`; a scenario judging branch
discipline needs a protected name there or the skill's skip clause fires),
`scenario_harnesses` lists the adapters the assertions have been checked
against (any other adapter refuses the run), and `scenario_model_tier`
asks for `small | medium | large`, which the adapter binds to a model
(`adapter_model`) — a small model is where a discipline slips first, and
the cheapest place to watch it.

A scenario with follow-up turns requires an adapter implementation of
`adapter_continue_behavioral`. Continuation must use the harness's structured
session identity; starting a fresh session and replaying prose is not equivalent.

**Make the exit code carry the verdict.** A written summary is produced by the
same agent that wants it green; an exit code is not. Assert what is easy to fake
and hard to see in a transcript: that an artifact exists, that it *loads*, and
that it can actually fail. The strongest assertions take something away and
require the gate to notice — gut the implementation and the test must go red;
restore the defect and the reproduction must go red.

**Ground the opening in the fixture.** An opening that presupposes something the
project does not contain scores the fixture, not the library: the agent correctly
answers that there is no such area and builds nothing, which is
indistinguishable from a skill that failed to change anything. `fixtures/`
says what exists, and `lib/prelude.sh` holds the helpers every scenario shares.

**Scenarios are shared by every harness.** A per-harness override exists only
for a real constraint — a single-turn CLI ends a run at the first clarifying
question with no deliverable, so `scenario_opening_<harness>()` pre-empts it.
A per-adapter `scenario_setup_<harness>()` override works the same way for
fixtures. Never use an override to make an arm look better, and say so when
you use one.

## Suites and manifests

`behavior/suites/all.txt` lists every scenario; a scenario not listed does
not run. `behavior/checks-manifest/<scenario>.json` freezes the static set
of judgment verbs the scenario calls — regenerated by
`bin/check --update-manifests`, enforced by `bin/check`, and compared at
run time: a scenario whose checks never executed cannot produce green, and
one whose manifest verbs never ran is `indeterminate`, not passed.

## Chain → scenario

One row per chain (`E-10` fills the rows):

| chain | scenario |
| --- | --- |
| bug-fix | debugging |
| new-feature | test-driven-development |
| plan-execution | plan-execution-entry |
| incident | containment-before-diagnosis |
| release | release-routing |

## Admission is deliberately strict

A scenario is retained only for **a failure actually observed**, with a verdict
that can be checked mechanically. Not an imagined gap, and not a coverage push:
these are the most expensive tests in the repository, and one that was never
grounded in a real defect costs hours to run and proves nothing when it passes.

| Selection | Runs | Per run | Wall clock |
| --- | --- | --- | --- |
| One scenario, one harness, one arm | 1 | ~5–40 min | — |
| Every scenario × 4 harnesses × 2 arms | 17 × 4 × 2 | ~5–40 min | **tens of hours** |

That matrix is **deliberately not filled**, and the limit is stated rather than
papered over. Run one skill on one harness before a sweep — if it fails
there, the rest of the matrix will not tell you anything new yet. The
primary flow is one scenario, one harness, one arm:

```bash
bin/behavior --harness opencode --scenario subagent-driven-development --arm green --plugin ../sdlc-skills
```

Live runs are **not deterministic**. Report the runs you actually did, failures
included, and never commit a result except as a record under `results/`.

A mandatory ordering boundary has no majority threshold. If one valid run
crosses the boundary in the wrong order, that run is a failure requiring action;
two passing runs do not cancel it.
