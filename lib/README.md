# lib/

Shared seams the runners source — and nothing else shared. Each file has
one offline test under `lib/tests/` that builds its own throwaway stand-ins,
so no test needs a sibling plugin checkout or a live CLI.

- `common.sh` — `log`, `die`, `require_tool` (127 on the first missing
  tool), `lab_run_dir`, `lab_root`, `plugin_root`.
- `home-env.sh` — `lab_home_env <run-dir>` prints the per-run `HOME`,
  `XDG_*`, `TMPDIR`, and `LAB_RUN_BASE` assignments (eval them); the home
  lives under `${TMPDIR:-/tmp}/sdlc-skills-evals/<run-id>/`, never under
  the repository. `lab_seed_credentials <run-dir> <harness>` copies only
  that harness's seed files (mode 0600); without a seed dir it succeeds
  quietly. `lab_home_cleanup <run-dir>` removes the whole run tree —
  register it on `EXIT`.
- `pin.sh` — `lab_inventory_commit` prints the committed upstream pin;
  `lab_pin_tree` and `lab_pin_note` resolve and describe a `--plugin`;
  `lab_pin_identity <path|ref> <skill>` prints `{commit, skill_tree}` for
  the skill text that tree holds (nulls, with the reason on stderr, for a
  directory that is not a clean git work tree);
  `lab_pin_plugin <path|ref> <run-dir>` prints the resolved commit (a
  directory is used as is; a ref becomes a throwaway worktree under the run
  dir) and `lab_pin_cleanup` removes pins. Capture-safe: no caller trap
  fires early inside `$(...)`; a caller that needs the worktree past a
  capture pins without capturing. Refuses unknown refs and non-checkout
  roots (exit 2) — never a global install.
- `stream-text.sh` — `lab_extract_stream_text <stream> [harness]` prints
  the last answer text a run's stream carries (a terminal summary, else the
  last whole assistant message, else the joined deltas), never tool calls,
  tool output, or reasoning; `bin/evaluate` writes it to
  `outputs/response.txt`.

`lib/tests/` also holds the offline stand-ins every suite shares:
`fake-cli/` (a scripted agent CLI the adapters launch under test) and
`tripwire/` (one shim per real agent CLI name; `lib/tests/ci-static.sh` puts
it first on `PATH` so any suite that reaches a real CLI fails).
