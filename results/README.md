# results/

Dated records: `results/<date>-<skill>-<harness>/` for an evaluation and
`results/<date>-<skill>-<harness>-triggering/` for a triggering run. A
record is committed
only when a maintainer deliberately records one; everything under `raw/` and
every `workspaces/` iteration is ignored and never committed.

## What a record is

`bin/report --workspace workspaces/<campaign>/iteration-<N> --record
results/<date>-<skill>-<harness>` copies an evaluated iteration into a
record, and refuses — copying nothing — if any target already exists:

- `benchmark.json` — per configuration (`with_skill` and `without_skill`,
  or `old_skill`): `pass_rate`, `time_seconds`, and `tokens` as mean ±
  stddev over all scored runs of that configuration, `indeterminate_count`,
  and the delta between the two configurations. An `indeterminate` arm has
  a null pass rate and stays out of the mean. `runs[]` holds one row per
  eval, configuration and run, each with its `run_number` (1 to
  `runs_per_eval`). Its `metadata` says what was measured: `skill`,
  `harness`, `harness_version` (null when the adapter reads none),
  `model` (the one every session named; null when the adapter reads none,
  a session named none, or two disagreed — never a guess),
  `runs_per_eval` (the `--runs` of the iteration), `plugin` —
  `{commit, skill_tree}` for `with_skill` —
  and `baseline`, the same pair for `old_skill` and null for
  `without_skill`.
- `benchmark.md` — the same table, rendered.
- `feedback.json` — your review of the outputs (`{"reviews": [...]}`).

With one run the stddev means nothing: it is the spread between the evals,
not between runs of the same eval. A record uses 3
(`bin/evaluate --runs 3`). `bin/benchmark` writes a `benchmark.json` only
for an iteration where every eval and arm holds runs 1 to `runs_per_eval`.

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

The identity is exact only where git converts nothing in the skill
directory on checkout. Where it does (`core.autocrlf=true`, or an
`eol=crlf`, `filter` or `ident` attribute, for example), the files a run
installs can differ in bytes from the tree the record names, and the run
is still identified — from a commit as from a directory, because `git
archive` converts the same way. A directory that holds a symlink as a
plain file (`core.symlinks=false`) is identified too.

## What a triggering record is

`bin/triggering --summary <path>` writes one JSON object beside its
per-query output, and `bin/report --triggering <path> --record
results/<date>-<skill>-<harness>-triggering` copies it to
`triggering.json` in the record, and nothing else:

- `metadata` — `skill`, `harness`, `harness_version` and `model` (null
  under the rules above: `model` is the one every scored run named),
  `plugin` — `{commit, skill_tree}` as above — `description_sha256`,
  `runs` (repetitions per query), and `threshold` (0.5: a query that
  should trigger passes at a trigger rate above 0.5, one that should not
  passes below it, and a rate of exactly 0.5 fails either way). The
  verdict is decided on the rate rounded to two decimals, as the sheet
  prints it, while `trigger_rate` is exact: the two can disagree only for
  a query with more than 100 conclusive runs.
- `splits` — for each of `train`, `validation`, and `holdout` a query ran
  in: `queries`, `passed`, `failed`, `inconclusive`, and `pass_rate`,
  which is passed / (passed + failed) and null when every query in the
  split was inconclusive.
- `queries` — one row per query: `query`, `should_trigger`, `split`,
  `trigger_rate` (null for an inconclusive query), and `verdict` (`PASS`,
  `FAIL`, or `INCONCLUSIVE`). `trigger_rate` is over the runs that were
  conclusive, which can be fewer than `runs`: a run the provider refused,
  or one whose record could not be read, is left out of the rate, and the
  row does not say how many were.

`description_sha256` is the SHA-256 of the exact bytes of the frontmatter
line that begins `description:` in the skill's `SKILL.md`, without its
newline. The frontmatter is the block a first line of exactly `---` opens
and the next line of exactly `---`, or the end of the file, closes, and
the line is the first one in it that begins `description:`. The newline
is the one LF byte that ends the line; every other byte is hashed as it
is, a CR that ends the line included. The same value, by hand:

```bash
LC_ALL=C awk 'NR == 1 { if ($0 != "---") exit; next }
              $0 == "---" { exit }
              /^description:/ { printf "%s", $0; exit }' SKILL.md | sha256sum
```

It is null when the tree has no such line, or the line changed while the
run was under way; the run says so when it starts or when it ends. A
`SKILL.md` with CRLF line endings has no such line: its first line is not
exactly `---`. For a file with no such line the command above hashes
nothing and prints the SHA-256 of the empty string (`e3b0c442…`), which
no record carries. The `SKILL.md` is the one at
`skills/[<phase>/]<name>/` in the tree the run installed.

`bin/report --triggering` refuses — copying nothing — when
`triggering.json` already exists in the record, when
`metadata.plugin.skill_tree` is not a git tree hash (the null cases are
the ones listed above), when `metadata.description_sha256` is not 64
lowercase hex digits, and when the summary has no validation query: a
record reports the validation split, so a `--split train` or `--split
holdout` summary stays in `workspaces/`, and `bin/triggering` says so in
its plan and when the run starts. A failing or inconclusive query is
recorded like any other, a validation split whose queries were all
inconclusive included. No transcript, stream, or log enters the summary.

## Naming the run

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
