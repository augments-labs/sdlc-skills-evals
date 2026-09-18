# results/

Dated campaign records: `results/<date>-<label>/`. A record is committed
only when a maintainer deliberately records one — self-test runs
(`results/*-selftest-*/`) and everything under `raw/` are ignored and
never committed.

## What a record is

- `campaign.json` — frozen inputs: `{plugin_ref, plugin_commit, harness,
  arms: [{name, base}], suite, scenarios, runs, tier, lab_commit, created}`
- `runs/<scenario>-<arm>-<n>.json` — one file per executed run:
  `{scenario, arm, harness, plugin_commit, verdict, stage, checks_run,
  tokens, duration_ms, workdir}`
- `chains.json` — written by hand before `report`: one entry per chain
  (`chain`, `task`, `harness`, `turns`, `wasted_steps`)
- `grading/`, `benchmark.json`, `feedback.json` — output-eval artifacts
  (`bin/campaign --evals`, from `E-6` on)
- `summary.md` — rendered by `bin/campaign report`: `## Commit`,
  `## Behavior scenarios` (result, runs, pass count, indeterminate count
  as a separate column), `## Chains` (from `chains.json` when present),
  `## Costs` (tokens and wall time per arm, `unknown` where the harness
  reports none), `## Against baseline` (with `--against`)

## What never is

`raw/` (session streams and logs), run homes (they live under `TMPDIR`,
never here), transcripts, credential files, `*.jsonl`. The record is
sanitized before commit — see `SECURITY.md`. Negative results are
recorded at equal billing to wins: a failing record is data, not shame.
