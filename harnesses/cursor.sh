#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Cursor CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `cursor-agent` CLI: how the plugin
# is loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: documentation-grounded, runtime unverified.
#   - The install facts come from the pinned upstream's tests/harnesses/cursor.sh
#     (upstream 638040d, v11.0.0): cursor loads every directory under
#     `~/.cursor/plugins/local/`, reads `.cursor-plugin/plugin.json` and falls
#     back to `.claude-plugin/plugin.json`, and rejects a symlink there that
#     points outside it — so the tree is COPIED, not linked.
#   - The flags and the event protocol come from cursor-agent 2026.10.01's
#     own shipped bundle: `--print` with `--output-format stream-json` writes
#     one JSON object per line, and the emitter builds
#     `{"type":"assistant","message":{...},"session_id":...}` and
#     `{"type":"tool_call","subtype":"started"|"completed","call_id":...,
#       "tool_call":{"toolCallId":...,"toolName":...,"argsJson":"..."}}`.
#   - How a skill is loaded comes from the same bundle: cursor resolves a
#     skill from the path of its SKILL.md — the directory above SKILL.md is
#     the skill's name — so the structural skill-invocation record is a
#     tool call whose arguments name a SKILL.md.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/cursor/. No cursor stream has been
#     observed on this machine, so every capability below is documentation
#     and `runnable` stays `no` until a real run replaces the label.
#
# ISOLATION. Every launch runs under an environment this file builds
# explicitly (cursor_env): the throwaway home, the XDG directories inside
# it, a runtime directory and a dead session-bus socket inside it. The
# operator's environment is NOT inherited: it carries the operator's own
# session bus, their SSH agent, their IDE tokens and their credential
# helpers, and a launch that inherited them could read the operator's
# stored credentials. The one exception is the operator's credential seed
# ($LAB_CREDENTIAL_SEED/cursor/env), which the runner exports for a
# harness whose auth is environmental: it is sourced INSIDE the child
# process, so its values reach the CLI and never reach a command line, a
# log or this shell.

adapter_name='cursor'

runnable=no
runnable_reason="cursor-agent 2026.10.01 is on PATH and its stream-json emitter is in its own shipped bundle, but no cursor run has been recorded on this machine"
permission_flags="--force"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=yes(documentation) post-compaction-event=unknown(documentation)"

source_cursor_home="${CURSOR_HOME:-${HOME:-}/.cursor}"

# THE LAUNCH ENVIRONMENT, built explicitly (see the header).
cursor_env() {
  CURSOR_ENV=(
    "PATH=$PATH"
    "HOME=$harness_home"
    "XDG_CONFIG_HOME=$harness_home/.config"
    "XDG_DATA_HOME=$harness_home/.local/share"
    "XDG_CACHE_HOME=$harness_home/.cache"
    "XDG_RUNTIME_DIR=$harness_home/.runtime"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$harness_home/.runtime/bus"
    "TMPDIR=$harness_home/tmp"
  )
  mkdir -p "$harness_home/.config" "$harness_home/.local/share" "$harness_home/.cache" \
           "$harness_home/.runtime" "$harness_home/tmp"
}

# Run the CLI under that environment, with the operator's credential seed
# sourced inside the child when there is one.
cursor_exec() { # $@ the CLI and its arguments
  local seed="${LAB_CREDENTIAL_SEED:-}/$adapter_name/env"
  if [ -f "$seed" ]; then
    timeout "$timeout_s" env -i "${CURSOR_ENV[@]}" \
      sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' _ "$seed" "$@"
  else
    timeout "$timeout_s" env -i "${CURSOR_ENV[@]}" "$@"
  fi
}

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v cursor-agent >/dev/null 2>&1 || { echo "no \`cursor-agent\` CLI on PATH" >&2; return 3; }
}

# Isolated HOME with the tree placed where a user's clone goes:
# `~/.cursor/plugins/local/<name>/`, which cursor loads at session start.
#
# The copy takes the files git would clone plus untracked ones, so the
# working tree under test is what lands. Cursor has no command that installs
# a single plugin, so the copy IS the install.
#
# The NONE arm is an isolated home with no plugin folder at all.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  local dest="$harness_home/.cursor/plugins/local/sdlc-skills"
  mkdir -p "$dest"
  git -C "$1" ls-files -z --cached --others --exclude-standard 2>>"$errlog" |
    tar -C "$1" --null --ignore-failed-read -T - -cf - 2>>"$errlog" |
    tar -C "$dest" -xf - 2>>"$errlog" || {
    echo "copying the checkout into $dest failed (see $errlog)" >&2; return 1; }
  plugin_dir="$dest"
  return 0
}

# The plugin comes from the copied folder, not from a flag.
adapter_activation_flags() { :; }

# No suffix: cursor runs the plugin's SessionStart hook, which injects the
# router, so the opening goes in bare.
adapter_prompt_suffix() { :; }

# DETECTION: a `tool_call` record whose arguments name a SKILL.md. Cursor
# resolves a skill from the path of its SKILL.md (the directory above it is
# the skill's name), so that read IS the structural skill-invocation record.
# `argsJson` is the tool's argument object, serialized as a JSON string.
adapter_chain() { # $1 stream file (JSONL from --output-format stream-json)
  jq -r 'select(.type == "tool_call")
         | (.tool_call.toolName // "") as $t
         | (.tool_call.argsJson // "") as $a
         | select($t == "read" or $t == "Read" or $t == "read_file" or $t == "view_file")
         | ($a | try fromjson catch {}) as $i
         | ($i.path // $i.filePath // $i.file_path // "") as $p
         | select($p | test("SKILL[.]md$"))
         | ($p | sub("/+$";"") | split("/") | .[-2] // empty)' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.type == "tool_call")
         | (.tool_call.toolName // "") as $t
         | ((.tool_call.argsJson // "") | try fromjson catch {}) as $i
         | ($i.path // $i.filePath // $i.file_path // "") as $p
         | if ($t == "read" or $t == "Read" or $t == "read_file" or $t == "view_file")
              and ($p | test("SKILL[.]md$"))
           then "SKILL " + ($p | sub("/+$";"") | split("/") | .[-2] | tostring)
           elif ($t == "edit" or $t == "Edit" or $t == "write" or $t == "Write")
           then "EDIT " + $p
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? An `assistant` record means the model spoke; a dead provider
# emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .type == "assistant")' >/dev/null 2>&1 <"$1"
}

# NO adapter_usage: cursor's stream-json emitter records the assistant's
# text and its tool calls, and no token or cost field. The runner reports
# this harness's wall clock and states that tokens are unreported, which is
# true, instead of inventing a number.

# Activation probe: one query, bounded by the wall clock. `--mode plan` is
# cursor's read-only mode; the workdir is a disposable fixture and HOME is
# the throwaway run home.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  cursor_env
  ( cd "$wd" && cursor_exec cursor-agent --print --output-format stream-json --mode plan \
        --workspace "$wd" "$@" "$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home. `--force` is cursor's permission
# flag: it pre-approves commands that are not explicitly denied.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  cursor_env
  ( cd "$1" && cursor_exec cursor-agent --print --output-format stream-json --force \
        --workspace "$1" "$(cat "$2")" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the prior
# stream's own `session_id`; an absent id is an adapter error, not a
# fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r 'select(.session_id? != null) | .session_id' "$prior" 2>/dev/null | head -1)"
  [ -n "$session_id" ] || { echo "Cursor stream contains no resumable session id" >&2; return 2; }
  cursor_env
  ( cd "$wd" && cursor_exec cursor-agent --print --output-format stream-json --force \
        --resume "$session_id" --workspace "$wd" "$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}

# NO adapter_model: cursor's --model takes a model id and its own list of
# models; no official small/medium/large mapping exists. A scenario that
# asks for a tier is refused by the runner rather than run on the default
# model and called that tier.
