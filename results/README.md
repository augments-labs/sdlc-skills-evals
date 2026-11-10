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
  stays out of the mean. Its `metadata` says what was measured: `skill`,
  `harness`, `harness_version` (null when the adapter reads none),
  `model` (the one every session named; null when the adapter reads none,
  a session named none, or two disagreed — never a guess),
  `runs_per_eval`, `plugin` — `{commit, skill_tree}` for `with_skill` —
  and `baseline`, the same pair for `old_skill` and null for
  `without_skill`.
- `benchmark.md` — the same table, rendered.
- `feedback.json` — your review of the outputs (`{"reviews": [...]}`).

`commit` is the full commit the arm's tree came from: the one a reference
was archived from, or `HEAD` of a directory. `skill_tree` is the git tree
hash of the skill's directory at that commit:
`git rev-parse <commit>:skills/<phase>/<name>`. It identifies the skill
text by content, so it still matches after a squash merge changes the
commit.

`bin/report` also refuses — copying nothing — an iteration that cannot say
which skill text it measured: `plugin.skill_tree` is not a git tree hash,
or the second arm is `old_skill` and `baseline.skill_tree` is not one. It
says which arm. `bin/evaluate` writes a null there when `--plugin` or
`--baseline-plugin` was:

- a reference the plugin checkout has no commit for;
- a reference or a directory's `HEAD` whose commit holds no single
  `skills/[<phase>/]<name>/SKILL.md`;
- a directory that is not the top of a git work tree with a commit, or one
  git cannot report on;
- a directory whose skill directory is not exactly `HEAD`'s: a modified,
  untracked or git-ignored file in it, a file mode `HEAD` does not hold, or
  a file marked `assume-unchanged` or `skip-worktree`;
- a tree whose identity changed while the run was under way.

An iteration with no readable `identity.json` has a null identity too. Run
it from a commit or a clean work tree. What the run scored is never a
reason: a failing or indeterminate result is recorded like any other.

Name the `--dry-run` that priced the run in the PR that commits the
record. A description optimization is not recorded here:
`bin/optimize-description` leaves its iterations, `optimization.json`,
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
