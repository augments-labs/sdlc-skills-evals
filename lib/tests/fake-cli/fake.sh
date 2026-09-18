#!/usr/bin/env bash
# Fake harness adapter for offline runner tests. Sourced, never executed.
#
# A TEST DOUBLE, not a model of any CLI: its canned stream is bare
# "SKILL <name>" / "EDIT <path>" lines (no real adapter may imitate this
# grep-shaped stream; real detection is structural), driven by FAKE_MODE. Modes: ok (emits a
# SKILL line unless FAKE_CHAIN=0), timeout (outlives timeout_s),
# error (exit 1), blocked (provider-refusal pattern), dead (empty
# stream). FAKE_UNAVAILABLE=1 makes adapter_check fail.
# FAKE_TOKENS=1 makes adapter_usage report a number, else silence.

adapter_name='fake'

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
  return 0
}

adapter_activation_flags() { :; }
adapter_prompt_suffix() { :; }
adapter_model() { printf 'fake-%s\n' "$1"; }
adapter_model_flags() { return 0; }

adapter_chain() { # $1 stream
  grep -h '^SKILL ' "$1" 2>/dev/null | sed 's/^SKILL //'
}

adapter_behavioral_events() { # $1 stream
  grep -h -E '^(SKILL|EDIT) ' "$1" 2>/dev/null
}

adapter_ran() { # $1 stream — any line means the (fake) model spoke
  [ -s "$1" ]
}

adapter_usage() { # $1 stream
  [ -n "${FAKE_TOKENS:-}" ] || return 0
  printf '42\n'
}

_fake_emit_ok() { # $1 stream
  # FAKE_SUBJECT lets the triggering runner's subject matching hit;
  # FAKE_CHAIN=0 or FAKE_FIRE=0 emits no chain (a clean baseline).
  if [ "${FAKE_CHAIN:-1}" != 0 ] && [ "${FAKE_FIRE:-1}" != 0 ]; then
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
    *) _fake_emit_ok "$3"; return 0;;
  esac
}

adapter_run_activation() { # $1 workdir $2 prompt $3 stream
  # Mirrors the real adapters: the wall clock bounds the run, and the
  # runner sees 124 on timeout.
  export -f _fake_body _fake_emit_ok
  timeout "${timeout_s:-5}" bash -c '_fake_body "$@"' _ "$@"
}

adapter_run_behavioral() { # $1 workdir $2 opening file $3 stream
  adapter_run_activation "$1" "behavioral" "$3"
}

adapter_continue_behavioral() { # $1 workdir $2 prompt $3 new stream $4 prior
  adapter_run_activation "$1" "$2" "$3"
  cat "$3" >> "$4"
}
