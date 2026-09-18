#!/usr/bin/env bash
# Offline test: throwaway per-run home. No live run, no credentials needed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../home-env.sh
source "$here/../home-env.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }
t() { # $1 description $2... command — passes iff the command exits 0
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

run_dir="$(mktemp -d)"
trap 'lab_home_cleanup "$run_dir" 2>/dev/null; rm -rf "$run_dir"' EXIT

# the assignments point outside the repository, never at the host HOME
orig_tmp="${TMPDIR:-/tmp}"
eval "$(lab_home_env "$run_dir")"
[ -n "${HOME:-}" ] && [ "$HOME" != "$run_dir" ] && [ "$HOME" != "$PWD" ] && ok "HOME redirected away from host and repo" || bad "HOME redirected away from host and repo (got ${HOME:-empty})"
case "$HOME" in "$orig_tmp"/*) ok "HOME lives under TMPDIR";; *) bad "HOME lives under TMPDIR (got $HOME)";; esac
case "$HOME" in "$PWD"/*) bad "HOME is outside the lab root";; *) ok "HOME is outside the lab root";; esac
t "home directory exists" test -d "$HOME"
t "XDG_CONFIG_HOME follows HOME" test "${XDG_CONFIG_HOME:-}" = "$HOME/.config"
t "XDG_DATA_HOME follows HOME" test "${XDG_DATA_HOME:-}" = "$HOME/.local/share"
t "XDG_CACHE_HOME follows HOME" test "${XDG_CACHE_HOME:-}" = "$HOME/.cache"

# seeding with no seed dir is a no-op success, never a failure
t "seed with no seed dir succeeds quietly" lab_seed_credentials "$run_dir" fake-harness

# seeding copies only that harness's files, mode 0600
seed="$(mktemp -d)"
mkdir -p "$seed/fake-harness" "$seed/other-harness"
printf 'secret' > "$seed/fake-harness/creds.json"
printf 'secret' > "$seed/other-harness/creds.json"
LAB_CREDENTIAL_SEED="$seed" lab_seed_credentials "$run_dir" fake-harness >/dev/null 2>&1
t "seeded credential lands in the run home" test -f "$HOME/creds.json"
[ ! -f "$HOME/other-harness/creds.json" ] && [ "$(find "$HOME" -name 'creds.json' | wc -l)" -eq 1 ] && ok "only that harness's files are seeded" || bad "only that harness's files are seeded"
t "seeded credential is mode 0600" test "$(stat -c %a "$HOME/creds.json")" = "600"
rm -rf "$seed"

# cleanup removes the whole run tree
lab_home_cleanup "$run_dir"
t "cleanup removes the run home" test '!' -e "$HOME"

exit "$fails"
