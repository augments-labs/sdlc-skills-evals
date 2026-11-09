#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Muse Code CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `muse` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: observed envelope, runtime unverified.
#   - The install facts come from the pinned upstream's tests/harnesses/muse.sh
#     (upstream 638040d, v11.0.0): muse 1.3.0 ships no plugin loader, so the
#     install is one `muse skills install <dir> --scope user` per canonical
#     skill directory, run by the plugin's own
#     scripts/sh/install-muse-skills.sh. Both HOME and XDG_CONFIG_HOME point
#     at the throwaway directory, and MUSE_NO_AUTO_UPDATE keeps the launcher
#     off the network.
#   - The event envelope was OBSERVED on muse 1.4.11-R6667.1 on this machine
#     with `muse exec --json --provider echo`: one JSON object per line, each
#     with `schema_version`, `id`, `stream` (the session the record belongs
#     to), `sequence`, `record_type`, `payload_type` and `payload`. The
#     observed payload types include `run.output.delta` (the text),
#     `run.usage` (per-model token counts) and `run.terminal.completed` (the
#     close of a run).
#   - A skill-invocation record is NOT covered by that observation: the
#     echo provider makes no tool call. The tool-call record family is
#     muse's own (`tool.*` payload types in the 1.4.11 binary), and a skill
#     invocation is matched by the `sdlc-skills:` namespace the plugin
#     format carries, or by a SKILL.md path. That part is
#     documentation-grounded, not observed.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/muse/. No skill-loading run has been
#     recorded on this machine, so `runnable` stays `no` until a real run
#     replaces the label.
#
# ISOLATION. Every invocation of the CLI runs under an environment this file
# builds explicitly (muse_env): the throwaway home, the XDG directories
# inside it, a runtime directory and a dead session-bus socket inside it,
# and the launcher's auto-update switch off. The operator's environment is
# NOT inherited: it carries the operator's own session bus, their SSH
# agent, their IDE tokens and their credential helpers, and an invocation
# that inherited them could read the operator's stored credentials. The one
# exception is the operator's credential seed ($LAB_CREDENTIAL_SEED/muse/env),
# which the runner exports for a harness whose auth is environmental: it is
# sourced INSIDE the child process, so its values reach the CLI and never
# reach a command line, a log or this shell.

adapter_name='muse'

runnable=no
runnable_reason="muse 1.4.11 is on PATH and its exec --json envelope was observed here, but no skill-loading run has been recorded on this machine"
permission_flags="--approval-mode never"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=no(documentation) post-compaction-event=no(documentation)"

# THE LAUNCH ENVIRONMENT, built explicitly (see the header).
muse_env() {
  MUSE_ENV=(
    "PATH=$PATH"
    "HOME=$harness_home"
    "XDG_CONFIG_HOME=$harness_home/.config"
    "XDG_DATA_HOME=$harness_home/.local/share"
    "XDG_CACHE_HOME=$harness_home/.cache"
    "XDG_RUNTIME_DIR=$harness_home/.runtime"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$harness_home/.runtime/bus"
    "MUSE_NO_AUTO_UPDATE=1"
    "TMPDIR=$harness_home/tmp"
  )
  mkdir -p "$harness_home/.config" "$harness_home/.local/share" "$harness_home/.cache" \
           "$harness_home/.runtime" "$harness_home/tmp"
}

# Run the CLI under that environment, with the operator's credential seed
# sourced inside the child when there is one.
muse_exec() { # $@ the CLI and its arguments
  local seed="${LAB_CREDENTIAL_SEED:-}/$adapter_name/env"
  if [ -f "$seed" ]; then
    timeout "$timeout_s" env -i "${MUSE_ENV[@]}" \
      sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' _ "$seed" "$@"
  else
    timeout "$timeout_s" env -i "${MUSE_ENV[@]}" "$@"
  fi
}

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v muse >/dev/null 2>&1 || { echo "no \`muse\` CLI on PATH" >&2; return 3; }
}

# Isolated home, installed the way scripts/sh/install-muse-skills.sh installs
# for a real user: one `muse skills install <dir> --scope user` per canonical
# skill directory, which copies each skill under the Muse config
# directory's `skills/`. Offline and without credentials — a local-path
# install touches no provider.
#
# Both HOME and XDG_CONFIG_HOME point at the throwaway directory: muse
# resolves its config directory from XDG_CONFIG_HOME when that is set and
# from HOME otherwise, and overriding only one of them would let the
# operator's real `~/.config/muse/skills/` answer for the tree under test.
# MUSE_NO_AUTO_UPDATE keeps the launcher from reaching the network.
#
# plugin_dir stays unset: nothing is copied to a plugin root here, so the
# throwaway home is where the installed skills live.
#
# The NONE arm is an isolated home with no skills installed.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  muse_env
  ( cd "$1" && env -i "${MUSE_ENV[@]}" \
      bash scripts/sh/install-muse-skills.sh ) >>"$errlog" 2>&1 || {
    echo "install-muse-skills.sh failed (see $errlog)" >&2; return 1; }
  return 0
}

# The plugin comes from the installed skills, not from a flag.
adapter_activation_flags() { :; }

# No suffix: muse 1.3.0 runs no plugin hook, so nothing injects the router
# and the skill has to be invoked. The opening goes in bare.
adapter_prompt_suffix() { :; }

# DETECTION: a tool-call record whose payload names a skill. The record is
# identified structurally by its payload type (muse's own `tool.*` family);
# within it, the skill is named either by the `sdlc-skills:` namespace the
# plugin format carries or by a SKILL.md path, whose directory above it is
# the skill's name. A namespace token in any OTHER record is not an
# activation: the payload-type gate is what makes this structural.
adapter_chain() { # $1 stream file (JSONL from muse exec --json)
  jq -r 'select((.payload_type // "") | test("tool"))
         | (.payload // {} | tostring) as $all
         | ([$all | match("(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md"; "g")]
            | map(.captures[0].string) | .[0]) as $dir
         | ([$all | match("sdlc-skills:(?<skill>[A-Za-z0-9_-]+)"; "g")]
            | map(.captures[0].string) | .[0]) as $ns
         | if $dir != null then $dir
           elif $ns != null then $ns
           else empty end' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select((.payload_type // "") | test("tool"))
         | (.payload // {} | tostring) as $all
         | ([$all | match("(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md"; "g")]
            | map(.captures[0].string) | .[0]) as $dir
         | ([$all | match("sdlc-skills:(?<skill>[A-Za-z0-9_-]+)"; "g")]
            | map(.captures[0].string) | .[0]) as $ns
         | if $dir != null then "SKILL " + $dir
           elif $ns != null then "SKILL " + $ns
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? The terminal record is muse's own close of a run; a dead
# provider emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .payload_type == "run.terminal.completed"
                   or .payload_type == "run.terminal.failed")' \
    >/dev/null 2>&1 <"$1"
}

# COST: the observed `run.usage` record carries the run's per-model token
# counts under `models[]`. They are added. Silent when no usage record is
# present, so a timed-out or refused run reports no number rather than a
# misleading zero.
adapter_usage() { # $1 stream file
  jq -s '([.[] | select(.payload_type == "run.usage") | .payload.models[]?
            | (.input_tokens // 0) + (.output_tokens // 0)]
          | map(select(. != null)) | add) // empty' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock. `--trust-workspace`
# is what makes muse load a workspace's skills and rules at all; the
# approval mode stays on-request so nothing is auto-approved.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  muse_env
  ( cd "$wd" && muse_exec muse exec --json --trust-workspace --approval-mode on-request "$@" "$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  muse_env
  ( cd "$1" && muse_exec muse exec --json --trust-workspace --approval-mode never "$(cat "$2")" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the prior
# stream's own `stream.id` — the observed envelope carries it on every
# record — and is handed back with `--session-id`. An absent id is an adapter
# error, not a fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r 'select(.stream.kind? == "session") | .stream.id // empty' \
    "$prior" 2>/dev/null | head -1)"
  [ -n "$session_id" ] || { echo "Muse stream contains no resumable session id" >&2; return 2; }
  muse_env
  ( cd "$wd" && muse_exec muse exec --json --trust-workspace --approval-mode never \
        --session-id "$session_id" "$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}

# NO adapter_model: muse takes `--model` and `--reasoning-effort`, but no
# official small/medium/large mapping exists. A scenario that asks for a
# tier is refused by the runner rather than run on the default model and
# called that tier.
