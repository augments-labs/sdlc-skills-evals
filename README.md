# sdlc-skills-evals

The eval lab for [sdlc-skills](https://github.com/augments-labs/sdlc-skills), pinned to upstream commit
`40f8ff4c532da29b286b4d06ecf4516a4a093a7d` (package version `11.2.0`) in
`config/upstream-inventory.json`. It runs the two
[agentskills.io](https://agentskills.io) workflows for one skill on one
harness at a time:

1. **Does a skill change what gets built?** — evaluating skills:
   `bin/evaluate` runs each case of `evals/<skill>/evals.json` twice, with
   the skill installed and without it, then `bin/grade` scores each arm's
   produced files, `bin/benchmark` aggregates the iteration, and
   `bin/report` copies it into a record.
2. **Does a description trigger?** — optimizing descriptions:
   `bin/triggering` scores a skill's `description` against its query set
   `descriptions/<skill>.json`; `bin/optimize-description` revises it on the
   `train` failures and keeps the iteration with the best `validation` rate.

## Safety model

- **You run it; nothing else does.** Every live command spends your own
  harness account and is started by you, from your terminal, after its
  `--dry-run` has priced it. No agent working on this repository launches
  one (`CLAUDE.md`), and public CI runs static checks only (`shellcheck`,
  `bin/check`, `lib/tests/*.sh` under a tripwire that fails on any real
  agent CLI) — see `SECURITY.md`.
- **Every run gets a throwaway home** under `TMPDIR` (never under this
  repository): `HOME`, `XDG_*`, and `TMPDIR` are redirected per arm and
  removed on exit. Raw streams, session logs, and run homes are sensitive
  and are never committed.
- **Unobserved is `indeterminate`.** An arm that timed out, exited
  non-zero, was refused by the provider, ran no model turn, or — as the
  control — loaded a skill anyway measured nothing: it scores a null pass
  rate and is counted apart, never averaged in as a pass or a fail.
- **Records, not code**, under `results/` and `docs/` — enforced by
  `bin/check`.

## Running it yourself

Prerequisites:

- a harness whose adapter header says `runnable=yes` (`opencode` and
  `claude-code` today; `harnesses/README.md` says how a `runnable=no`
  harness is verified by hand), with its CLI on your `PATH` and logged in
  to your own account — the lab carries no key;
- the plugin checkout at `SDLC_SKILLS_ROOT` (default `../sdlc-skills`)
  holding the pinned commit. `--plugin` takes a directory or a ref in that
  checkout and defaults to the inventory's commit; whichever you use is
  recorded with the run.

Price every live command with its own `--dry-run` first: it prints the pin,
the selection, and the exact number of CLI calls, and launches nothing.

### Evaluating a skill

```bash
bin/evaluate --harness opencode --skill yagni --dry-run
bin/evaluate --harness opencode --skill yagni
```

Outputs land in `workspaces/<campaign>/` (default campaign
`evaluate-<skill>`), one `iteration-<N>/` per run: per eval and arm the
produced `outputs/`, `run_status.json`, `timing.json`, and `grading.json`,
then `benchmark.json`, `benchmark.md`, and an empty `feedback.json` for
your review. `--baseline-plugin` pairs the skill against an older plugin
tree (`old_skill`) instead of no skill.

Prose assertions wait as `needs_review` for you. To have a skill-free
session on the same harness grade them, price the extra calls first —
`bin/grade` has no dry run, so `bin/evaluate` prices the grader:

```bash
bin/evaluate --harness opencode --skill yagni --grade-with-harness --dry-run
bin/evaluate --harness opencode --skill yagni --grade-with-harness
```

After you edit assertions, re-grade an arm offline, re-aggregate, and
promote the iteration to a record (`--harness` on `bin/grade` is the live
rubric grader, one call per arm with prose):

```bash
bin/grade workspaces/evaluate-yagni/iteration-1/<eval-id>/with_skill
bin/grade workspaces/evaluate-yagni/iteration-1/<eval-id>/with_skill --harness opencode
bin/benchmark workspaces/evaluate-yagni/iteration-1
bin/report --workspace workspaces/evaluate-yagni/iteration-1 --record results/<date>-yagni-opencode
```

### Optimizing a description

```bash
bin/triggering --harness opencode --skill yagni --dry-run
bin/triggering --harness opencode --skill yagni
bin/optimize-description --harness opencode --skill yagni --plugin ../sdlc-skills --apply --dry-run
bin/optimize-description --harness opencode --skill yagni --plugin ../sdlc-skills --apply
```

`bin/triggering` is the before-number. `bin/optimize-description` scores
up to `--max-iterations` candidates under
`workspaces/<campaign>/iteration-<i>/`, shows the reviser only the `train`
failures, and writes `best-description.txt`, `optimization.json`, and
`optimization.md`. `--apply` writes the winner into every `SKILL.md` copy
of the skill in the `--plugin` directory, which must be a writable
checkout you review with `git diff` there; without `--apply` nothing
outside `workspaces/` changes. A fresh holdout, written only after the
selection, is scored once with `--split holdout`
(`descriptions/holdout/README.md`).

A record cites the plugin commit it ran against; quote its `results/` path
when referring to it. The lab itself is never versioned, tagged, or
released — a record pins `lab_commit`, which is the only lab identity
anything cites.

## Layout

- `bin/` — `evaluate`, `grade`, `benchmark`, `report`, `triggering`,
  `optimize-description`, `check`
- `lib/` — shared seams (throwaway home, plugin pinning, stream text) plus
  offline `lib/tests/` with a fake CLI and the CI tripwire
- `harnesses/` — one launcher per agent CLI; an unrunnable harness yields
  `indeterminate`
- `evals/` — `evals/<skill>/evals.json` and the `files/` project each
  case runs in
- `descriptions/` — `descriptions/<skill>.json` query sets (`train` /
  `validation` splits; fresh `holdout/` sets written after selection)
- `fixtures/` — the seeded project `bin/triggering` points queries at
- `results/` — dated records (committed only when a maintainer
  deliberately records one)
- `docs/` — authoring, triage, coverage, and harness guides
- `workspaces/` — run iterations (never committed)

## Environment variables

| Variable | Meaning | Default |
| --- | --- | --- |
| `SDLC_SKILLS_ROOT` | the plugin checkout under test; the lab points at the plugin, never the reverse | `../sdlc-skills` resolved from the lab root (`SDLC_SKILLS_EVALS_ROOT`), so every `bin/*` command works from any working directory including a nested worktree |
| `SDLC_SKILLS_EVALS_ROOT` | this repository's root | resolved from the command's own location |
| `INVENTORY_PATH` | the committed pin and skill/harness inventory | `config/upstream-inventory.json` |
| `EVALS_ROOT` | output-eval root for `bin/evaluate` and the shape check | `evals/` under the lab root |
| `DESCRIPTIONS_ROOT` | query-set root for `bin/triggering`, `bin/optimize-description`, and the shape check | `descriptions/` under the lab root |
| `DOCS_ROOT` | guide root for the records-not-code rule | `docs/` under the lab root |
| `WORKSPACES_ROOT` | where `bin/evaluate` and `bin/optimize-description` write iterations | `workspaces/` under the lab root |
| `TMPDIR` | parent for per-run homes and workdirs | system default |
| `LAB_CREDENTIAL_SEED` | directory of per-harness credential seeds (`<seed>/<harness>/`) copied into run homes | `~/.config/sdlc-skills-evals/credentials` for `bin/evaluate`; seeding is a quiet no-op when it is absent |
