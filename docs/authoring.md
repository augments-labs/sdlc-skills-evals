# Writing an eval set or a query set

Write the smallest probe that can surprise you, then freeze it. Every live
run below is started by the user, after its `--dry-run`; an agent authoring
these files verifies them offline only (`bin/check`, `lib/tests/*.sh`).

## An eval set (`evals/<skill>/evals.json`)

The agentskills.io evaluating-skills workflow: does the skill change what
gets built?

1. Pick the failure you actually observed — a real session, a real miss.
   No observed failure, no case. The directory is named for the skill's
   directory under the pinned plugin's `skills/`.
2. Write 2–3 cases: `id`, `prompt` (realistic paths, names, backstory;
   vary phrasing and detail), `expected_output`, and `assertions`. Include
   one edge case. Never name the skill, the criteria, or the check in the
   prompt — that tests obedience, not behavior.
3. Put the project the prompts talk about under `evals/<skill>/files/`.
   `bin/evaluate` stages that whole tree into every arm's working
   directory, seeds it as one git commit, and copies any extra `files`
   entries a case lists on top (paths relative to `evals/<skill>/`, never
   escaping it). Every path a prompt names must exist in it — `bin/check`
   fails a prompt that points at a missing file. Small on purpose: the
   agent reads it on every run.
4. A new set starts with empty `assertions` and
   `"pending_first_run": true`. Run the pair (`bin/evaluate`, priced
   first) and read what each arm produced in `outputs/`.
5. Write assertions from the outputs you saw, against produced files,
   never transcript prose. Make them mechanical where possible:

   - `[check:file-exists <path>]`
   - `[check:file-contains <path> <regex>]`
   - `[check:file-not-contains <path> <regex>]` (an absent file fails)
   - `[check:command-succeeds <cmd...>]` (full shell, CWD `outputs/`)
   - `[check:git-count <min>]` (files added, modified, or deleted vs the
     seed commit, committed or not; a rename git detects counts once; when
     the list cannot be computed, as when the agent replaced the repository,
     the check is `needs_review`, never a count of zero)

   An assertion without a `[check:` prefix is prose: `bin/grade` records it
   `needs_review` for you, or for the rubric grader under `--harness`. An
   unknown verb is also `needs_review`, never a pass. Set
   `pending_first_run` to `false` once the set has assertions;
   `bin/check` requires the key either way.
6. Hand-verify each mechanical check against three states before trusting
   it: the broken project (must fail), the symptom-only fix (must fail),
   the root-cause fix (must pass). A check that cannot tell all three apart
   is decoration.
7. Grade, benchmark, review `feedback.json`, then revise the skill and run
   the next iteration. Generalize each fix (`do X because Y causes Z`,
   never `ALWAYS/NEVER`) and keep the skill lean.

Trust note: `command-succeeds` runs a full shell. Eval files are
lab-authored and reviewed like code; never grade eval files from untrusted
input.

## A query set (`descriptions/<skill>.json`)

The agentskills.io optimizing-descriptions workflow: does the description
fire on the openings it should, and stay quiet on the near-misses?

1. Write at least ten positives and ten near-miss negatives, each with
   `query`, boolean `should_trigger`, and `split` (`train` or
   `validation`); every negative also names the neighbouring activity it
   expects in `expect`.
2. Keep validation between a quarter and a half of the set, in the same
   positive-to-negative proportion as train. Once assigned, a query's split
   is frozen (`docs/upstream-coverage.md` records the assignment).
3. Ground each query in `fixtures/fixtures.sh` whenever its verb presupposes
   what it names.
4. Run `bin/check`; then price and run `bin/triggering`, and
   `bin/optimize-description` to revise.

`descriptions/README.md` covers the shape rules, near-miss craft, and cost.
A holdout (`descriptions/holdout/<skill>.json`) is written only after a
selection — see `descriptions/holdout/README.md`.
