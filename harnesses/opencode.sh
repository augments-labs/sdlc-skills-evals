#!/usr/bin/env bash
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

runnable=yes
runnable_reason="opencode 1.x on PATH; auth is infrastructure-provided on this machine, no seed needed"
permission_flags="--auto"
capabilities="subagent-loads-skills=run nesting-depth=run tier-settable=documentation session-start-event=documentation post-compaction-event=documentation edit-path-partial=run"

adapter_name='opencode'

adapter_check() {
  command -v opencode >/dev/null 2>&1 || { echo "no \`opencode\` CLI on PATH" >&2; return 3; }
}

# OpenCode loads a plugin file directly: the isolated config home carries
# only the plugin entry naming the pinned source. An empty source is the
# NONE arm — isolated home, no plugin entry, so nothing can leak in.
# Auth is infrastructure-provided here; where it is not, the runner exports
# $LAB_CREDENTIAL_SEED/opencode/env before invoking (see harnesses/README).
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  mkdir -p "$harness_home/xdg/opencode" || return 3
  # A step bound for the default build agent when the runner names one
  # (maxturns): opencode has no CLI turns flag, so the isolated config
  # carries it. Past the bound the agent answers text-only and exits —
  # a miss, not a hang. Without maxturns the wall clock is the only bound.
  local plug_cfg steps_cfg
  if [ -n "${1:-}" ]; then
    plug_cfg="$(jq -n --arg p "$1/.opencode/plugins/sdlc-skills.js" '[$p]')"
  else
    plug_cfg="null"
  fi
  if [ -n "${maxturns:-}" ]; then
    steps_cfg="$(jq -n --argjson n "$maxturns" '{build:{steps:$n}}')"
  else
    steps_cfg="null"
  fi
  jq -n --argjson plugin "$plug_cfg" --argjson agent "$steps_cfg" \
    '{"$schema":"https://opencode.ai/config.json"}
     + (if $plugin == null then {} else {plugin:$plugin} end)
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
  ( exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      XDG_CONFIG_HOME="$harness_home/xdg" XDG_DATA_HOME="$harness_home/xdg" \
      TMPDIR="${TMPDIR:-/tmp}" \
      opencode run --format json --auto --dir "$wd" "$@" "$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a
# real checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  ( exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      XDG_CONFIG_HOME="$harness_home/xdg" XDG_DATA_HOME="$harness_home/xdg" \
      TMPDIR="${TMPDIR:-/tmp}" \
      opencode run --format json --auto --dir "$1" "$(cat "$2")" ) \
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
  ( exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      XDG_CONFIG_HOME="$harness_home/xdg" XDG_DATA_HOME="$harness_home/xdg" \
      TMPDIR="${TMPDIR:-/tmp}" \
      opencode run --format json --auto --dir "$wd" -s "$session_id" "$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}
