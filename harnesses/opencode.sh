#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# OpenCode CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `opencode` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# Detection keys below were observed, not assumed: part type/tool names and
# the skill/edit/write input shapes come from the operator's own session
# store (part.type/tool/state.input.name, edit+write state.input.filePath);
# the `run --format json` envelope (one JSON object per line, sessionID
# beside every event, step-finish tokens) from a real --format json stream.
# The jq walks are envelope-agnostic (`..`) so envelope revisions do not
# silently zero the chain — an unmatched stream yields no chain, never a
# phantom. XDG_CONFIG_HOME isolation verified by skill count (empty config:
# built-ins only; real config: 37 sdlc skills). Provisional until a recorded
# run confirms them: adapter_ran (no dead-CLI shape observed) and the
# session-continue path (sessionID key observed, resume unobserved).
#
# TWO GENERATIONS install the same plugin differently, so the major version
# decides (the pinned upstream's tests/harnesses/opencode.sh, v11.0.0): 1.x
# takes a plugin FILE under `plugin`; 2.x takes a plugin DIRECTORY under
# `plugins` and resolves `<dir>/index.js` inside it, refusing a file path
# outright. The install below writes the layout the CLI on this machine
# actually reads.
#
# ISOLATION. Every launch runs under an environment this file builds
# explicitly (opencode_env): the throwaway home, the XDG directories inside
# it, a runtime directory and a dead session-bus socket inside it. The
# operator's environment is NOT inherited: it carries the operator's own
# session bus, their SSH agent, their IDE tokens and their credential
# helpers, and a launch that inherited them could read the operator's
# stored credentials. The one exception is the operator's credential seed
# ($LAB_CREDENTIAL_SEED/opencode/env), which the runner exports for a
# harness whose auth is environmental: it is sourced INSIDE the child
# process, so its values reach the CLI and never reach a command line, a
# log or this shell.

runnable=yes
runnable_reason="opencode on PATH; the recorded activation evidence is a 1.x stream, and the install covers the pinned upstream's 1.x and 2.x plugin layouts"
permission_flags="--auto"
capabilities="subagent-loads-skills=yes(run) nesting-depth=yes(run) tier-settable=unknown(documentation) session-start-event=unknown(documentation) post-compaction-event=unknown(documentation) edit-path-partial=yes(run)"

adapter_name='opencode'

# THE LAUNCH ENVIRONMENT, built explicitly (see the header).
opencode_env() {
  OPENCODE_ENV=(
    "PATH=$PATH"
    "HOME=$harness_home"
    "XDG_CONFIG_HOME=$harness_home/xdg"
    "XDG_DATA_HOME=$harness_home/xdg"
    "XDG_CACHE_HOME=$harness_home/.cache"
    "XDG_RUNTIME_DIR=$harness_home/.runtime"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=$harness_home/.runtime/bus"
    "TMPDIR=$harness_home/tmp"
  )
  mkdir -p "$harness_home/xdg" "$harness_home/.cache" "$harness_home/.runtime" \
           "$harness_home/tmp"
}

# Run the CLI under that environment, with the operator's credential seed
# sourced inside the child when there is one.
opencode_exec() { # $@ the CLI and its arguments
  local seed="${LAB_CREDENTIAL_SEED:-}/$adapter_name/env"
  if [ -f "$seed" ]; then
    timeout "$timeout_s" env -i "${OPENCODE_ENV[@]}" \
      sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' _ "$seed" "$@"
  else
    timeout "$timeout_s" env -i "${OPENCODE_ENV[@]}" "$@"
  fi
}

# `opencode --version` prints e.g. `opencode v2.0.13`; keep only the number.
# The probe runs under an environment of its own — a throwaway home, no
# operator variable — so a version check cannot reach the operator's
# session bus or their credential helpers either.
_opencode_detect() {
  local probe_home
  probe_home="$(mktemp -d)" || return 1
  opencode_version="$(env -i PATH="$PATH" HOME="$probe_home" \
    opencode --version 2>/dev/null | head -1 | tr -cd '0-9.')"
  rm -rf "$probe_home"
  opencode_major="${opencode_version%%.*}"
}

adapter_check() {
  command -v opencode >/dev/null 2>&1 || { echo "no \`opencode\` CLI on PATH" >&2; return 3; }
  _opencode_detect
  case "$opencode_major" in
    1|2) ;;
    *) echo "unrecognised \`opencode\` version: ${opencode_version:-none}" >&2; return 3;;
  esac
}


# OpenCode loads a plugin from the checkout, so the checkout is the whole
# install: the plugin resolves its skills from its own location. The isolated
# config home carries only the plugin entry — no credentials. An empty source
# is the NONE arm — isolated home, no plugin entry, so nothing can leak in.
# Auth is infrastructure-provided here; where it is not, the runner exports
# $LAB_CREDENTIAL_SEED/opencode/env before invoking (see harnesses/README).
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/xdg/opencode" || return 3
  # The layout depends on the major version: 1.x names a plugin FILE under
  # `plugin`, 2.x names the plugin DIRECTORY under `plugins` and resolves
  # `<dir>/index.js` inside it. The version is read at install time, never
  # carried over from an earlier install.
  _opencode_detect
  case "$opencode_major" in
    1|2) ;;
    *) echo "unrecognised \`opencode\` version: ${opencode_version:-none}" >&2; return 3;;
  esac
  # A step bound for the default build agent when the runner names one
  # (maxturns): opencode has no CLI turns flag, so the isolated config
  # carries it. Past the bound the agent answers text-only and exits —
  # a miss, not a hang. Without maxturns the wall clock is the only bound.
  local plug_cfg steps_cfg
  if [ -n "${1:-}" ]; then
    if [ "$opencode_major" = "1" ]; then
      plug_cfg="$(jq -n --arg p "$1/.opencode/plugins/sdlc-skills.js" '[$p]')"
    else
      plug_cfg="$(jq -n --arg p "$1" '[$p]')"
    fi
  else
    plug_cfg="null"
  fi
  if [ -n "${maxturns:-}" ]; then
    steps_cfg="$(jq -n --argjson n "$maxturns" '{build:{steps:$n}}')"
  else
    steps_cfg="null"
  fi
  local plugin_key="plugin"
  [ "$opencode_major" = "1" ] || plugin_key="plugins"
  jq -n --arg key "$plugin_key" --argjson plugin "$plug_cfg" --argjson agent "$steps_cfg" \
    '{"$schema":"https://opencode.ai/config.json"}
     + (if $plugin == null then {} else {($key):$plugin} end)
     + (if $agent == null then {} else {agent:$agent} end)' \
    > "$harness_home/xdg/opencode/opencode.json" || return 3
  plugin_dir="$1"
  return 0
}

# The plugin comes from the installed config, not from flags.
adapter_activation_flags() { return 0; }

# DETECTION: only a structured `skill` tool part counts. Bare directory
# names (observed: "using-git-worktrees", never "sdlc-skills:...") — the
# runner normalizes the prefix when comparing against the subject skill.
adapter_chain() { # $1 stream file (JSONL from --format json)
  jq -r '.. | objects | select(.tool == "skill")
         | (.state.input.name // .state.metadata.name // empty)' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r '.. | objects | select(.type == "tool")
         | if .tool == "skill" then "SKILL " + (.state.input.name // .state.metadata.name // "")
           elif .tool == "edit" or .tool == "write"
           then "EDIT " + (.state.input.filePath // "")
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? Any text, tool, or reasoning part means the model spoke. A
# dead provider emits none of these. Provisional: no dead-CLI shape has
# been observed on this machine to sharpen this against.
adapter_ran() { # $1 stream file
  jq -es '[.[] | .. | objects | select(.type == "text" or .type == "tool" or .type == "reasoning")] | length > 0' \
    >/dev/null 2>&1 <"$1"
}

# COST: the step-finish part carries the run's own totals (observed keys:
# total/input/output/reasoning/cache.read/cache.write). A long session emits
# one step-finish per step, so slurp the whole stream and take the LAST
# totals (cumulative). The explicit total wins; otherwise sum what is
# present. Silent when absent, so a timed-out or refused run reports no
# number rather than a misleading zero — and never a concatenation.
adapter_usage() { # $1 stream file
  jq -s '[.[] | .. | objects | select(.type == "step-finish" and (.tokens | type == "object")) | .tokens] | last
      | select(. != null)
      | .total // ((.input // 0) + (.output // 0) + (.reasoning // 0)
                   + ((.cache.read // 0) + (.cache.write // 0)))' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock (opencode exposes
# no per-turn bound; a healthy negative answers and exits on its own).
# --auto approves what is not denied — contained because the workdir is a
# disposable fixture and HOME/XDG are the throwaway run home.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  opencode_env
  ( opencode_exec opencode run --format json --auto --dir "$wd" "$@" "$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a
# real checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  opencode_env
  ( opencode_exec opencode run --format json --auto --dir "$1" "$(cat "$2")" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the
# prior stream's own sessionID; an absent id is an adapter error, not a
# fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r '.. | objects | .sessionID? // .session_id? // empty' "$prior" 2>/dev/null \
    | grep -v '^null$' | head -1)"
  [ -n "$session_id" ] || { echo "opencode stream contains no resumable session id" >&2; return 2; }
  opencode_env
  ( opencode_exec opencode run --format json --auto --dir "$wd" -s "$session_id" "$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}