# behavior/evals/

Output evals: does a skill produce good outputs, compared against a
baseline. The standard's evaluating-skills procedure, as files:

- `evals.json` per skill — `{skill_name, evals[]}` where each eval has
  `id`, `prompt` (realistic, with paths and context), `expected_output`,
  optional `files` (input files copied into the run workdir), and
  `assertions[]`. Start with 2–3 cases; vary phrasing and detail; include
  one edge case. Write `assertions` only **after** the first recorded run,
  from the outputs you actually saw — until then the file carries
  `"pending_first_run": true` and empty assertions.
- Workspace — `workspaces/<campaign>/iteration-N/<eval-id>/{with_skill,
  without_skill|old_skill}/{outputs/,timing.json,grading.json}`, plus
  `iteration-N/benchmark.json` and `feedback.json`. One iteration per
  skill revision; the next revision runs in `iteration-N+1`.
- `timing.json` — `{total_tokens, duration_ms}` per arm run (`null`
  tokens when the harness reports none — never zero).
- `grading.json` — per assertion `{text, passed, evidence}` where passed
  is `true`, `false`, or `"needs_review"`, plus `summary: {passed,
  failed, needs_review, total, pass_rate}`. Written by `bin/grade`.
- `benchmark.json` — per-arm `{pass_rate, time_seconds, tokens}` as
  `{mean, stddev}` plus `delta` (with minus without). Written by
  `bin/benchmark`.
- `feedback.json` — human notes per eval id (`""` means fine), read on
  the next iteration. Written by hand.

## Grading principles

- A PASS needs concrete evidence: a quoted line, a path with a size, an
  exit code with output — never the benefit of the doubt. `bin/grade`
  enforces this for mechanical checks (`[check:<verb> args]` prefixes:
  `file-exists`, `file-contains`, `command-succeeds`, `git-count`); the
  rest is `needs_review` for a human with an evidence pointer.
- Review the assertions, not just the results: drop assertions that pass
  in both arms (they inflate the score without measuring the skill) and
  investigate ones that fail in both (broken check or too hard).
- The pair that matters is with-pass / without-fail: that delta is the
  skill's measured value. High variance across runs means ambiguous
  instructions — tighten them, add an example, rerun.

## Cost

An eval pair is two agent runs. Price first:

```bash
bin/campaign --evals --dry-run --plugin ../sdlc-skills --harness opencode --skill verification-before-completion
```

then run the pair into a workspace iteration, grade, benchmark, review,
and only then revise the skill and run the next iteration. When an
iteration is worth keeping, copy its benchmark into the record with
`bin/report --workspace workspaces/<campaign>/iteration-N --record
results/<date>-<label>/` — the copy under `results/` is canonical.
