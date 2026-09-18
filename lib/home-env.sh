#!/usr/bin/env bash
# Throwaway per-run home. Sourced, never executed.
#
# Every live run gets its own HOME under ${TMPDIR:-/tmp}/sdlc-skills-evals/,
# never under the repository and never the host HOME. Derived from the
# run-dir's basename so parallel runs cannot share a home.
# lab_home_cleanup removes the whole run tree; register it on EXIT.

_lab_run_base() { # $1 run-dir -> prints the run's base directory
  # LAB_RUN_BASE (printed by lab_home_env) wins: TMPDIR is reassigned per
  # run, so recomputing from $TMPDIR after eval would point elsewhere.
  if [ -n "${LAB_RUN_BASE:-}" ]; then printf '%s' "$LAB_RUN_BASE"; return 0; fi
  printf '%s/sdlc-skills-evals/%s' "${TMPDIR:-/tmp}" "$(basename "$1")"
}

lab_home_env() { # $1 run-dir — prints VAR=value assignments; eval them
  [ "$#" -eq 1 ] || return 127
  local base home
  base="${TMPDIR:-/tmp}/sdlc-skills-evals/$(basename "$1")"
  home="$base/home"
  mkdir -p "$home" "$base/tmp" || return 127
  printf 'LAB_RUN_BASE=%s\n' "$base"
  printf 'HOME=%s\n' "$home"
  printf 'XDG_CONFIG_HOME=%s/.config\n' "$home"
  printf 'XDG_DATA_HOME=%s/.local/share\n' "$home"
  printf 'XDG_CACHE_HOME=%s/.cache\n' "$home"
  printf 'TMPDIR=%s\n' "$base/tmp"
}

lab_seed_credentials() { # $1 run-dir $2 harness — copies only that harness's seed files, mode 0600
  [ "$#" -eq 2 ] || return 127
  local base home seed
  base="$(_lab_run_base "$1")"
  home="$base/home"
  [ -d "$home" ] || return 127
  seed="${LAB_CREDENTIAL_SEED:-$HOME/.config/sdlc-skills-evals/credentials}/$2"
  [ -d "$seed" ] || return 0
  cp -r "$seed/." "$home/" || return 127
  find "$home" -type f -exec chmod 0600 {} + || return 127
  return 0
}

lab_home_cleanup() { # $1 run-dir — removes the whole run tree
  [ "$#" -eq 1 ] || return 127
  rm -rf "$(_lab_run_base "$1")"
}
