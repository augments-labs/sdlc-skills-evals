# Reading a non-green result

A non-green result is a message about the lab, the harness, or the skill —
in that order. Work the list top to bottom; stop at the first that fits.
Unobserved is `indeterminate`, never a pass and never a fail.

## An evaluation (`bin/evaluate`)

Each arm's `run_status.json` says whether it measured anything
(`outcome: ok | indeterminate`, with `reason`, `exit_status`, `adapter_ran`,
`skill_chain`). An `indeterminate` arm scores `pass_rate: null`, is counted in
`benchmark.json`'s `indeterminate_count`, and stays out of the mean.

1. **Unrunnable harness.** `bin/evaluate` exits `2` before any run with
   "harness X is unrunnable here (reason)": its adapter says `runnable=no`.
   No account, no CLI, no run. Provision the harness and verify it by hand
   (`harnesses/README.md`), or accept the gap; never score absence as
   failure.
2. **Provider refusal** (`reason: provider refusal (auth or quota)`).
   Quota, login, or capacity. Fix the account, re-run, never average it in
   as a miss.
3. **Timeout** (`reason: timeout (exit 124 …)`). The wall clock cut the
   session off. Re-run with a larger `--timeout`; never score it.
4. **Non-zero exit** (`reason: the session exited N`). The CLI itself
   failed — read the arm's `stderr.txt`. A broken adapter fails every eval
   the same way; a sick run fails one. Some CLIs also exit non-zero when
   they run out of `--max-turns`, so a higher limit is the first retry.
5. **No model turn** (`reason: no model turn`). The session started and
   the model never answered. Treat it as 2 or 4 until the stream says
   otherwise.
6. **Contaminated control** (`reason: contaminated: without_skill loaded
   skill(s)`). The no-skill arm loaded skills anyway — usually an installed
   copy leaking through a real home. Fix the isolation and refuse the
   result; a passing control never erases a reported failure.
7. **Broken check.** A `[check:` assertion whose evidence says its command
   could not run, its file was absent, or its verb is unknown (which also
   leaves it `needs_review`) says nothing about the skill. Fix the check,
   not the skill, and settle a real defect versus a broken check by
   running the check against a known-good project (`docs/authoring.md`).
8. **Assertion failure.** The checks ran and did not hold. Read which one
   in `grading.json`: the assertions are the finding. Re-run once — live
   runs are non-deterministic — then treat a repeat as a real defect in
   the skill or the eval.
9. **`needs_review`.** A prose assertion, or a rubric grader answer that
   was missing, malformed, or did not name the assertion. Not a failure:
   read the arm's `outputs/`, decide, and record it in `feedback.json`.

## A description (`bin/triggering`, `bin/optimize-description`)

1. **Inconclusive run.** The harness never answered the query; it is
   dropped from the denominator, never scored as "did not fire". Fix the
   account or the harness first.
2. **A timeout or truncation on a negative.** Bounded non-observation is
   not proof the skill would never fire; report the count apart.
3. **train and validation disagree.** A description that improves on
   `train` while `validation` falls is overfitting the revision set; keep
   the iteration with the best `validation` rate, which
   `bin/optimize-description` already selects. Never move a validation
   failure into `train`.
4. **A query that cannot fire on the fixture.** A verb that presupposes a
   file the fixture lacks scores the fixture, not the description: fix the
   query and restart comparison (`descriptions/README.md`).

Report every non-green run with its reason. A red nobody can place is a
lab bug until proven otherwise.
