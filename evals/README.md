# evals/

One eval set per skill, for the agentskills.io evaluating-skills workflow:
does the skill change what gets built?

```text
evals/<skill>/evals.json   the cases
evals/<skill>/files/       the project every case runs in
```

`<skill>` is the skill's directory name under the pinned plugin's
`skills/`. `evals.json` holds `skill_name` and an `evals` array; each case
has `id`, `prompt`, `expected_output`, `assertions`, and an optional `files`
list. Every set records `pending_first_run`: `true` while it has no
assertions yet, `false` once they were written from an observed run.

`bin/evaluate` stages the whole `files/` tree into each arm's working
directory, then copies a case's `files` entries on top (paths relative to
`evals/<skill>/`, never escaping it), and seeds the result as one git
commit. Assertions are graded against what the arm produced there:
`[check:<verb> <args>]` ones mechanically, prose ones as `needs_review`.
`--runs N` repeats every case N times per arm, each repetition staged and
graded on its own.

`bin/check` validates every set's shape and that each path a prompt names
exists under `files/`. Writing a set: `docs/authoring.md`. Running one —
always priced with `--dry-run` first, and only by the user:
`README.md` `## Running it yourself`.
