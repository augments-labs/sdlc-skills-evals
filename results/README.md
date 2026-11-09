# results/

Dated records: `results/<date>-<skill>-<harness>/`. A record is committed
only when a maintainer deliberately records one; everything under `raw/` and
every `workspaces/` iteration is ignored and never committed.

## What a record is

`bin/report --workspace workspaces/<campaign>/iteration-<N> --record
results/<date>-<skill>-<harness>` copies an evaluated iteration into a
record, and refuses — copying nothing — if any target already exists:

- `benchmark.json` — per configuration (`with_skill` and `without_skill`,
  or `old_skill`): `pass_rate`, `time_seconds`, and `tokens` as mean ±
  stddev over the scored runs, `indeterminate_count`, and the delta between
  the two configurations. An `indeterminate` arm has a null pass rate and
  stays out of the mean.
- `benchmark.md` — the same table, rendered.
- `feedback.json` — your review of the outputs (`{"reviews": [...]}`).

Name the plugin commit the run pinned and the `--dry-run` that priced it in
the PR that commits the record. A description optimization is not recorded
here: `bin/optimize-description` leaves its iterations, `optimization.json`,
and `optimization.md` in `workspaces/`, and the description it selected
lands in the plugin through `--apply` and the plugin's own review.

`2026-09-18-sdd-opencode/` predates this shape (`campaign.json`, `runs/`,
`summary.md` from the retired runner) and is kept byte-identical as a
historical record.

## What never is

`raw/` (session streams and logs), run homes (they live under `TMPDIR`,
never here), produced `outputs/`, transcripts, credential files, `*.jsonl`.
The record is sanitized before commit — see `SECURITY.md`. Negative results
are recorded at equal billing to wins: a failing record is data, not shame.
