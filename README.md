# sdlc-skills-evals

The behavioral eval lab for [sdlc-skills](../sdlc-skills). It answers the two
questions no deterministic gate can, for one skill on one harness at a time:

1. **Does a description trigger?** — `bin/triggering` scores a skill's
   `description` against its query set in `descriptions/` (build-only here;
   no selection run ever starts from this lab).
2. **Does a skill change what gets built?** — `bin/behavior` runs a scenario
   from `behavior/scenarios/` against a live agent CLI and judges the
   produced artifacts, not the transcript prose.

## Safety model

- **Public CI runs static checks only** (`shellcheck`, `bin/check`,
  `lib/tests/*.sh`). Live runs need credentials and permissive agent CLIs
  and never run in CI — see `SECURITY.md`.
- **Every run gets a throwaway home** under `TMPDIR` (never under this
  repository): `HOME`, `XDG_*`, and `TMPDIR` are redirected per run and
  removed on exit. Raw streams, session logs, and run homes are sensitive
  and are never committed.
- **Verdicts are three-valued**: `pass | fail | indeterminate`. Anything
  unobserved (timeout, refusal, broken check, unrunnable harness, empty
  capture) is `indeterminate`, never a false red or green.
- **Records, not code**, under `results/` and `docs/` — enforced by
  `bin/check`.

## Quick start

Test one skill on one harness (the primary flow):

```bash
bin/behavior --harness opencode --scenario subagent-driven-development --arm green
```

Record a labelled, pinned set of runs once the tooling exists (`E-8`):

```bash
bin/campaign new sdd-opencode --plugin v10.2.1 --harness opencode --arms green --scenarios subagent-driven-development --runs 1
bin/campaign run sdd-opencode
bin/campaign report sdd-opencode
```

A record cites the plugin commit it ran against; quote its `results/` path
when referring to it. The lab itself is never versioned, tagged, or
released — a record pins `lab_commit`, which is the only lab identity
anything cites.

## Layout

- `bin/` — `behavior`, `triggering`, `campaign`, `grade`, `benchmark`,
  `report`, `check`
- `lib/` — shared seams (assertions, verdicts, throwaway home, plugin
  pinning) plus offline `lib/tests/`
- `harnesses/` — one launcher per agent CLI (`opencode.sh` is primary and
  carries `runnable=yes`; unrunnable harnesses yield `indeterminate`)
- `fixtures/` — small disposable projects scenarios are pointed at
- `descriptions/` — per-skill query sets (`train`/`validation` splits;
  fresh `holdout/` sets written after selection)
- `behavior/` — `scenarios/`, frozen `checks-manifest/`, `suites/`,
  per-skill `evals/`
- `results/` — dated campaign records (committed only when a maintainer
  deliberately records one)
- `docs/` — authoring, triage, and harness guides
- `workspaces/` — scratch space for eval iterations (never committed)

## Environment variables

| Variable | Meaning | Default |
| --- | --- | --- |
| `SDLC_SKILLS_ROOT` | the plugin checkout under test; the lab points at the plugin, never the reverse | `../sdlc-skills` resolved from the lab root (`SDLC_SKILLS_EVALS_ROOT`), so every `bin/*` command works from any working directory including a nested worktree |
| `SDLC_SKILLS_EVALS_ROOT` | this repository's root | resolved from the command's own location |
| `SDLC_SKILLS_PIN` | the plugin ref records pin | `v10.2.1` |
| `TMPDIR` | parent for per-run homes and workdirs | system default |
| `BH_DEFAULT_TIMEOUT` | per-arm wall clock for `bin/behavior` (inherited by the runner) | `1800` |
| `DESCRIPTIONS_ROOT` | query-set root for `bin/triggering` and the shape check | `descriptions/` under the lab root |
| `DOCS_ROOT` | guide root for the records-not-code rule | `docs/` under the lab root |
| `RELEASE` | plugin version for per-release records (`E-13` evaluator input) | unset |
| `LAB_CREDENTIAL_SEED` | directory of per-harness credential seeds (`<seed>/<harness>/`) copied into run homes | none — seeding is a quiet no-op without it |

Later tasks extend this table when they add a variable.
