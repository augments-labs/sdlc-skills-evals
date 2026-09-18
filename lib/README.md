# lib/

Shared seams every runner sources — and nothing else shared. Each file has
one offline test under `lib/tests/` that builds its own throwaway stand-ins,
so no test needs a sibling plugin checkout or a live CLI.

- `prelude.sh` — assertion verbs the scenarios call (`pass`, `fail`,
  `note`, `assert_contains`, `assert_not_contains`, `assert_file`,
  `assert_result`, `added_since_baseline`, `_af`, `ASSERT_MATCH`), plus
  `not` and the `_lab_checks_run` counter. Exit bands: 0 held, 1 did not
  hold, 127 broken check (wrong arity, missing tool); `not` never inverts
  127. All diagnostics go to stderr so stdout stays composable. Only the
  three `assert_*` predicates increment the counter — markers, the
  baseline helper, and `assert_result` do not — so a counter of zero means
  "no check ran".
- `verdict.sh` — `verdict_compose` over `{setup, run, capture, checks,
  manifest}` → `pass | fail | indeterminate` (exit 0/1/2). Any
  `indeterminate` wins over `fail`, `fail` over `pass`; an unknown stage
  word composes `indeterminate`.
- `home-env.sh` — `lab_home_env <run-dir>` prints the per-run `HOME`,
  `XDG_*`, `TMPDIR`, and `LAB_RUN_BASE` assignments (eval them); the home
  lives under `${TMPDIR:-/tmp}/sdlc-skills-evals/<run-id>/`, never under
  the repository. `lab_seed_credentials <run-dir> <harness>` copies only
  that harness's seed files (mode 0600); without a seed dir it succeeds
  quietly. `lab_home_cleanup <run-dir>` removes the whole run tree —
  register it on `EXIT`.
- `pin.sh` — `lab_pin_plugin <path|ref> <run-dir>` prints the resolved
  commit (a directory is used as is; a ref becomes a throwaway worktree
  under the run dir) and `lab_pin_cleanup` removes pins. Capture-safe: no
  caller trap fires early inside `$(...)`; a caller that needs the
  worktree past a capture pins without capturing. Refuses unknown refs
  and non-checkout roots (exit 2) — never a global install.
- `common.sh` — `log`, `die`, `require_tool` (127 on the first missing
  tool), `lab_run_dir`, `lab_root`, `plugin_root`.
