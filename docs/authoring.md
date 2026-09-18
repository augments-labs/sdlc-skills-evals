# Writing a scenario or an output eval

Write the smallest probe that can surprise you, then freeze it.

## A behavior scenario

1. Pick the failure you actually observed — a real session, a real miss.
   No observed failure, no scenario.
2. Copy the closest scenario in `behavior/scenarios/` and rename it for
   the skill, not the story.
3. Write `scenario_opening` first: the user's message verbatim, grounded
   in what the fixture contains. Never mention the skill, the criteria,
   or the check — the opening is private criteria; naming the skill
   tests obedience, not behavior.
4. Write `scenario_setup` from `fixtures/fixtures.sh`: reuse a fixture
   if one makes this failure possible, add one only if none does. Small
   on purpose — every line is read on every run.
5. Write `scenario_assert` against produced artifacts, never transcript
   prose: files that exist, files that load, gates that can fail. Judge
   only through the verbs in `lib/prelude.sh` (`pass`, `fail`,
   `assert_contains`, `assert_not_contains`, `assert_file`); `note`
   reports, `assert_result` closes, bare `echo` decides nothing.
6. Assert the same fact in two places (belt-and-braces): the artifact
   and an independent check on it. Treat disagreement as a triage flag,
   not a pass.
7. Hand-verify each check against three states before trusting it: the
   broken fixture (must fail), the symptom-only fix (must fail), the
   root-cause fix (must pass). A check that cannot tell all three apart
   is decoration.
8. Prefer an elicited fixture: generate the plan or project with the
   skill under test rather than hand-writing one that flatters it.
9. List the scenario in `behavior/suites/all.txt`, regenerate manifests
   (`bin/check --update-manifests`), run `bin/check`, and falsify
   deliberately: break the fixture and watch the scenario go red before
   any green run counts.

## An output eval (`behavior/evals/<phase>/<skill>/evals.json`)

1. Write 2–3 cases: `id`, `prompt` (realistic paths, names, backstory;
   vary phrasing and detail), `expected_output`, `files` when the prompt
   needs inputs. Include one edge case. Leave `assertions` empty with
   `"pending_first_run": true`.
2. Run the with/without pair (`bin/campaign --evals`, priced first).
3. Write assertions from the outputs you saw, tagged mechanical where
   possible (`[check:file-exists path]`, `[check:file-contains path
   regex]`, `[check:command-succeeds cmd]`, `[check:git-count min]`);
   prose assertions stay `needs_review`.
4. Grade, benchmark, review `feedback.json`, then revise the skill and
   run the next iteration. Generalize each fix (`do X because Y causes
   Z`, never `ALWAYS/NEVER`) and keep the skill lean.
