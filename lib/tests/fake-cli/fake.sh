#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Fake harness adapter for offline runner tests. Sourced, never executed.
#
# A TEST DOUBLE, not a model of any CLI: its canned stream is bare
# "SKILL <name>" / "EDIT <path>" lines (no real adapter may imitate this
# grep-shaped stream; real detection is structural), driven by FAKE_MODE. Modes: ok (emits a
# SKILL line unless FAKE_CHAIN=0), timeout (outlives timeout_s),
# error (exit 1), blocked (provider-refusal pattern), dead (empty
# stream). FAKE_UNAVAILABLE=1 makes adapter_check fail.
# FAKE_TOKENS=1 makes adapter_usage report a number, else silence.
# FAKE_NO_TIER=1 binds NO tier: the double has no adapter_model, so it
# stands for an adapter that cannot set one and the runner must refuse a
# run that asks for a tier.
# FAKE_ACTIVATION_HOOK=<exe> decides what an activation run fires: it is
# called as `<exe> <installed plugin dir> <prompt>` and each line it prints
# becomes a "SKILL <line>" record, so a test can make routing depend on the
# description the installed tree carries.
# Behavioral runs (reviser, paired and grader calls) are scripted by:
#   FAKE_RECORD_DIR=<dir>      records call-<n>/{prompt.txt,workdir,env}
#   FAKE_AUTH_FAIL=1           refuses as an unauthenticated CLI (exit 1)
#   FAKE_BEHAVIORAL_CHAIN="a b"  emits "SKILL a" "SKILL b"
#   FAKE_BEHAVIORAL_STDOUT=<text>  emits <text> as the answer
#   FAKE_BEHAVIORAL_HOOK=<exe> runs `<exe> <workdir> <opening> <stream>` in
#                              the workdir; its stdout is the stream
#   FAKE_BEHAVIORAL_EXIT=<n>   the launch's exit code (else the hook's)
# With none of the last five set, a behavioral run is the canned ok run.
# FAKE_RAN=0 makes adapter_ran report a refusal whatever the stream holds.
#
# The launch redirects its stderr to "$errlog", exactly as every real
# adapter does (harnesses/*.sh). The double keeps that contract on
# purpose: a runner that launches without setting errlog then aborts
# here, under `set -u`, instead of passing silently.

adapter_name='fake'

# The runner SOURCES this file. FAKE_SOURCE_LOG records that it happened,
# so a test can tell a path that only planned from a path that loaded an
# adapter at all.
# The HOME the adapter was sourced under, like the source_*_home every
# real adapter binds at source time: a test can tell the operator's home
# (where credentials are seeded from) from the run's throwaway one.
fake_source_home="${HOME:-}"
if [ -n "${FAKE_SOURCE_LOG:-}" ]; then
  printf 'sourced %s home=%s\n' "$adapter_name" "$fake_source_home" >> "$FAKE_SOURCE_LOG"
fi

runnable=yes
runnable_reason="offline test double — always runnable, never a live CLI"
# Test double: driven by FAKE_MODE env, passes no CLI flags. Exempt from
# the permission_flags rule that bin/check enforces on harnesses/*.sh.
permission_flags="none-test-double"
capabilities="test-double=yes(run)"

adapter_check() {
  [ -z "${FAKE_UNAVAILABLE:-}" ] || { echo "fake CLI unavailable" >&2; return 3; }
  return 0
}

adapter_install() { # $1 plugin source
  harness_home="$(mktemp -d)"
  plugin_dir="$1"
  # FAKE_LAUNCH_LOG records the tree the run installed, so a test can tell
  # a pinned tree from a moving checkout.
  if [ -n "${FAKE_LAUNCH_LOG:-}" ]; then
    printf 'install %s\n' "$1" >> "$FAKE_LAUNCH_LOG"
    # ...and the commit that tree is at. A pinned tree is a throwaway
    # worktree the runner removes at exit, so the path alone cannot say
    # WHICH tree was measured once the run is over.
    _fake_head=""
    [ -n "$1" ] && _fake_head="$(git -C "$1" rev-parse HEAD 2>/dev/null || printf 'none')"
    printf 'install-head %s\n' "$_fake_head" >> "$FAKE_LAUNCH_LOG"
  fi
  return 0
}

adapter_activation_flags() { :; }
adapter_prompt_suffix() { :; }
# A tier the adapter cannot set is modelled by NOT binding one: the
# runner refuses a run that asks for a tier rather than running the
# default model and calling it that tier.
if [ -z "${FAKE_NO_TIER:-}" ]; then
  adapter_model() { printf 'fake-%s\n' "$1"; }
  adapter_model_flags() { return 0; }
fi

adapter_chain() { # $1 stream
  grep -h '^SKILL ' "$1" 2>/dev/null | sed 's/^SKILL //'
}

adapter_behavioral_events() { # $1 stream
  grep -h -E '^(SKILL|EDIT) ' "$1" 2>/dev/null
}

adapter_ran() { # $1 stream — any line means the (fake) model spoke
  [ "${FAKE_RAN:-1}" != 0 ] || return 1
  [ -s "$1" ]
}

adapter_usage() { # $1 stream
  [ -n "${FAKE_TOKENS:-}" ] || return 0
  printf '42\n'
}

_fake_emit_ok() { # $1 stream [$2 prompt]
  # FAKE_SUBJECT lets the triggering runner's subject matching hit;
  # FAKE_CHAIN=0 or FAKE_FIRE=0 emits no chain (a clean baseline).
  if [ -n "${FAKE_ACTIVATION_HOOK:-}" ]; then
    "$FAKE_ACTIVATION_HOOK" "${FAKE_PLUGIN_DIR:-}" "${2:-}" | sed 's/^/SKILL /' >> "$1"
  elif [ "${FAKE_CHAIN:-1}" != 0 ] && [ "${FAKE_FIRE:-1}" != 0 ]; then
    printf 'SKILL %s\n' "${FAKE_SUBJECT:-fake-subject}" >> "$1"
  fi
  printf 'EDIT fixture-marker.txt\n' >> "$1"
}

_fake_body() { # $1 workdir $2 prompt $3 stream — the canned behavior
  case "${FAKE_MODE:-ok}" in
    timeout) sleep $(( ${timeout_s:-3} + 5 )); return 0;;
    error) return 1;;
    blocked) printf 'usage limit exceeded\n' >> "$3"; return 0;;
    dead) : > "$3"; return 0;;
    *) _fake_emit_ok "$3" "$2"; return 0;;
  esac
}

adapter_run_activation() { # $1 workdir $2 prompt $3 stream
  # Mirrors the real adapters: the wall clock bounds the run, and the
  # runner sees 124 on timeout. The launch's stderr goes to "$errlog",
  # the redirect every real adapter makes.
  # FAKE_LAUNCH_LOG records that the launcher was reached, so a test can
  # tell a run that launched from a path that only planned.
  if [ -n "${FAKE_LAUNCH_LOG:-}" ]; then
    printf 'activation %s\n' "$1" >> "$FAKE_LAUNCH_LOG"
  fi
  export FAKE_PLUGIN_DIR="${plugin_dir:-}"
  export -f _fake_body _fake_emit_ok
  timeout "${timeout_s:-5}" bash -c '_fake_body "$@"' _ "$@" 2>>"$errlog"
}

adapter_run_behavioral() { # $1 workdir $2 opening file $3 stream
  if [ -n "${FAKE_LAUNCH_LOG:-}" ]; then
    printf 'behavioral %s\n' "$1" >> "$FAKE_LAUNCH_LOG"
    # The tier the run asked for, as the runner handed it over: a
    # campaign's frozen tier is observable at the launch this way.
    printf 'tier %s\n' "${scenario_model_tier:-}" >> "$FAKE_LAUNCH_LOG"
  fi
  if [ -n "${FAKE_RECORD_DIR:-}" ]; then
    # What the launch was handed, kept for the test: the opening, the
    # workdir, and the environment the CLI would have run under.
    local n=1 rec
    while [ -e "$FAKE_RECORD_DIR/call-$n" ]; do n=$((n + 1)); done
    rec="$FAKE_RECORD_DIR/call-$n"
    mkdir -p "$rec"
    cp "$2" "$rec/prompt.txt" 2>/dev/null || : > "$rec/prompt.txt"
    printf '%s\n' "$1" > "$rec/workdir"
    {
      printf 'HOME=%s\n' "${HOME:-}"
      printf 'TMPDIR=%s\n' "${TMPDIR:-}"
      printf 'XDG_CONFIG_HOME=%s\n' "${XDG_CONFIG_HOME:-}"
      printf 'LAB_CREDENTIAL_SEED=%s\n' "${LAB_CREDENTIAL_SEED:-}"
      printf 'source_home=%s\n' "$fake_source_home"
      printf 'plugin_dir=%s\n' "${plugin_dir:-}"
    } > "$rec/env"
  fi
  if [ -z "${FAKE_BEHAVIORAL_HOOK:-}${FAKE_BEHAVIORAL_STDOUT:-}${FAKE_BEHAVIORAL_CHAIN:-}${FAKE_BEHAVIORAL_EXIT:-}${FAKE_AUTH_FAIL:-}" ]; then
    adapter_run_activation "$1" "behavioral" "$3"
    return
  fi
  if [ -n "${FAKE_AUTH_FAIL:-}" ]; then
    printf 'not authenticated\n' >> "$errlog"
    return 1
  fi
  local rc=0 s
  for s in ${FAKE_BEHAVIORAL_CHAIN:-}; do printf 'SKILL %s\n' "$s" >> "$3"; done
  [ -z "${FAKE_BEHAVIORAL_STDOUT:-}" ] || printf '%s\n' "$FAKE_BEHAVIORAL_STDOUT" >> "$3"
  if [ -n "${FAKE_BEHAVIORAL_HOOK:-}" ]; then
    ( cd "$1" && timeout "${timeout_s:-5}" "$FAKE_BEHAVIORAL_HOOK" "$1" "$2" "$3" ) \
      >> "$3" 2>>"$errlog" || rc=$?
  fi
  return "${FAKE_BEHAVIORAL_EXIT:-$rc}"
}

adapter_continue_behavioral() { # $1 workdir $2 prompt $3 new stream $4 prior
  adapter_run_activation "$1" "$2" "$3"
  cat "$3" >> "$4"
}