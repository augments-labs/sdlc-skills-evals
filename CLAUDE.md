# CLAUDE.md — agent guidance for sdlc-skills-evals

This repo is the behavioral eval lab for the `sdlc-skills` plugin
(`SDLC_SKILLS_ROOT`, default `../sdlc-skills` from the lab root). It tests
whether a skill changes what gets built, one skill on one harness at a time.

## Never

- **Never run a live eval in CI**, and never add one: public CI runs
  `shellcheck`, `bin/check`, and `lib/tests/*.sh` only. No API key, no live
  launch, no dangerous-mode flag in CI, ever.
- **Never commit secrets or run artifacts**: `.env`, credentials, session
  logs, `results/` runs (except a deliberately recorded campaign),
  `workspaces/`, `*.jsonl`, `*.log`. A leaked secret is rotated before any
  artifact is shared — see `SECURITY.md`.
- **Never commit code under `results/` or `docs/`**: records and guidance
  only (`bin/check` enforces this).
- **Never run a triggering selection loop**: `bin/triggering --dry-run`
  prices; the live loop runs nowhere here.
- **Never spend tokens while building**: build tasks are verified offline
  (self-tests against a fake CLI, JSON shape, `shellcheck`). A live run
  starts only after the maintainer records a go in
  `.sdlc-skills/decision-ledger.md`.

## Always

- One task per PR on `main`; the maintainer merges. Fill the PR template
  completely (risk notes, exact test commands and outcomes, record path).
- A live run pins the plugin (`--plugin <path|ref>`, frozen in
  `campaign.json`), uses a throwaway home under `TMPDIR`, and reports
  `pass | fail | indeterminate` — unobserved is `indeterminate`, never
  green or red.
- The lab itself is never versioned, tagged, or released.

## How to add to the lab

- A scenario: `behavior/scenarios/<name>.sh` with `scenario_opening`,
  `scenario_setup`, `scenario_assert` (assertions on produced artifacts,
  never on transcript prose); list it in `behavior/suites/all.txt`;
  generate its manifest (`bin/check --update-manifests`). See
  `docs/authoring.md`.
- A query set: `descriptions/<phase>/<skill>.json` with fixed
  `train`/`validation` splits and near-miss negatives; it must pass
  `bin/check`'s shape rules.
- A harness: one file under `harnesses/` implementing the launcher
  contract (`harnesses/README.md`); `runnable=no` with a reason until a
  real run on this machine proves otherwise. See
  `docs/adding-a-harness.md`.
- A result that is not green: read `docs/triage.md` before touching the
  scenario — a broken check is fixed in the check, not averaged away.
