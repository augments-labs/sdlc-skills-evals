# CLAUDE.md — agent guidance for sdlc-skills-evals

This repo is the eval lab for the `sdlc-skills` plugin (`SDLC_SKILLS_ROOT`,
default `../sdlc-skills` from the lab root), pinned to commit
`40f8ff4c532da29b286b4d06ecf4516a4a093a7d` (`11.2.0`) in
`config/upstream-inventory.json`. It runs the two agentskills.io workflows,
one skill on one harness at a time:

- **Evaluating skills:** `bin/evaluate` runs a skill's evals with the skill
  and without it, then `bin/grade` → `bin/benchmark` → `bin/report`.
- **Optimizing descriptions:** `bin/triggering` scores a description against
  its query set; `bin/optimize-description` revises it on `train` failures
  and keeps the iteration with the best `validation` rate.

## Never

- **User-run-only:** the lab ships code; the user runs it. No agent — this
  session, an executor, a worker, or a reviewer — ever launches a live
  `bin/evaluate`, `bin/optimize-description`, `bin/triggering` without
  `--dry-run`, `bin/grade --harness <real CLI>`, or any real agent CLI
  (`agy`, `claude`, `codex`, `cursor-agent`, `devin`, `grok`, `hermes`,
  `kimi`, `muse`, `opencode`, `pi`), during build, verification, review, or
  after it, with or without anyone's go. Agents may run `--dry-run` and the
  offline suites only. The user prices a run with `--dry-run` and starts it
  from their own terminal — see `README.md` `## Running it yourself`.
- **Never run a live eval in CI**, and never add one: the `static` workflow
  runs `shellcheck`, `bin/check`, and `lib/tests/*.sh` under the tripwire
  `PATH` (`lib/tests/ci-static.sh`) only. No API key, no live launch, no
  dangerous-mode flag in CI, ever.
- **Never spend tokens while building**: build tasks are verified offline
  (self-tests against the fake CLI in `lib/tests/fake-cli/`, JSON shape,
  `shellcheck`).
- **Never commit secrets or run artifacts**: `.env`, credentials, session
  logs, `workspaces/`, `raw/`, `*.jsonl`, `*.log`, and `results/` output
  except a deliberately recorded one. A leaked secret is rotated before any
  artifact is shared — see `SECURITY.md`.
- **Never commit code under `results/` or `docs/`**: records and guidance
  only (`bin/check` enforces this).

## Always

- One task per PR on `main`; the maintainer merges. Fill the PR template
  completely (risk notes, exact test commands and outcomes, record path).
- A live run pins the plugin (`--plugin <path|ref>`, default the inventory
  commit), uses a throwaway home under `TMPDIR`, and reports an unobserved
  arm (timeout, crash, refusal, no model turn, contaminated control) as
  `indeterminate` with a null pass rate — never as a pass or a fail.
- The lab itself is never versioned, tagged, or released.

## How to add to the lab

- An eval set: `evals/<skill>/evals.json` (a `skill_name` and 2–3 cases
  with `id`, `prompt`, `expected_output`, `assertions`, optional `files`), inputs
  under `evals/<skill>/files/`. Mechanical assertions use
  `[check:<verb> <args>]`; prose ones wait as `needs_review`. See
  `evals/README.md` and `docs/authoring.md`.
- A query set: `descriptions/<skill>.json` with fixed `train`/`validation`
  splits and near-miss negatives; it must pass `bin/check`'s shape rules
  and the frozen split assignment in `docs/upstream-coverage.md`. A
  holdout, written only after a selection, is
  `descriptions/holdout/<skill>.json`. See `descriptions/README.md`.
- A harness: one file under `harnesses/` implementing the launcher
  contract (`harnesses/README.md`); `runnable=no` with a reason until a
  real run on this machine proves otherwise. See
  `docs/adding-a-harness.md`.
- A result that is not green: read `docs/triage.md` before touching the
  eval — a broken check is fixed in the check, not averaged away.
