# Reading a non-green result

A non-green result is a message about the lab, the harness, or the skill —
in that order. Work the list top to bottom; stop at the first that fits.

1. **Assertion failure** (`verdict: fail`). The checks ran and did not
   hold. Read which one: the scenario's judgments are the finding. Re-run
   once — live runs are non-deterministic — then treat a repeat as a real
   defect in the skill or the scenario.
2. **Timeout** (`indeterminate`, stage `run`). The wall clock cut the run
   off. Nothing was observed; reschedule with a larger `--timeout`,
   never score it.
3. **Provider refusal** (`indeterminate`, stage `run`, "provider
   refused"). Quota, auth, or capacity. Fix the account, re-run, never
   average it in as a miss.
4. **Process error** (`indeterminate`, stage `run`, "adapter exited").
   The CLI itself failed — read `errlog` (path printed with `--keep`).
   Distinguish a broken adapter (same failure on every scenario) from a
   sick run (one scenario).
5. **Contaminated control** (`indeterminate`, stage `run`,
   "contaminated"). The no-skills arm loaded skills anyway — usually an
   installed copy leaking through the real user home. Fix the isolation,
   refuse the result; a passing control never erases a reported failure.
6. **Broken check** (exit `127`, `BROKEN` lines). Wrong arity, missing
   tool, or a `not` around a 127. The check never ran, so the verdict
   says nothing about the skill. Fix the check, not the skill — and a
   real defect versus a broken check is settled by re-running the check
   against a known-good fixture.
7. **Manifest mismatch** (`indeterminate`, stage `manifest`). The
   scenario's checks changed shape without regenerating manifests. If
   the change was deliberate, run `bin/check --update-manifests`; if
   not, find what stopped emitting.
8. **No checks ran** (`indeterminate`, stage `checks`). The scenario
   judged nothing — usually bare `echo` where verbs belong, or an early
   return that skipped them. Convert judgments to verbs.
9. **Unrunnable harness** (`indeterminate`, stage `harness`). No account,
   no CLI, no run. Provision the harness or accept the gap; never score
   absence as failure.

Report every non-green run with its stage. A red nobody can place is a
lab bug until proven otherwise.
