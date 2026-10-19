#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Codex CLI adapter. Sourced by the runners under tests/ — behavioural,
# plugin-smoke, and trigger-eval — never executed directly.
#
# ISOLATION. Every invocation of the CLI runs under an environment this file
# builds explicitly (codex_env): the throwaway home, the CLI's own
# CODEX_HOME — which is where the credentials file is copied — the XDG
# directories inside the throwaway home, a runtime directory and a dead
# session-bus socket inside it. The operator's environment is NOT inherited:
# it carries the operator's own session bus, their SSH agent, their IDE
# tokens and their credential helpers, and an invocation that inherited them
# could read the operator's stored credentials. The one exception is the
# operator's credential seed ($LAB_CREDENTIAL_SEED/codex/env), which the
# runner exports for a harness whose auth is environmental: it is sourced
# INSIDE the child process, so its values reach the CLI and never reach a
# command line, a log or this shell.

adapter_name='codex'

runnable=no
runnable_reason="not verified on this machine — credentials exist but no run observed"
permission_flags="--approve-for-me"
capabilities="subagent-loads-skills=yes(documentation) nesting-depth=unknown(documentation) tier-settable=no(run) session-start-event=unknown(documentation) post-compaction-event=unknown(documentation)"

source_codex_home="${CODEX_HOME:-${HOME:-}/.codex}"

# THE LAUNCH ENVIRONMENT, built explicitly (see the header).
codex_env() {
  CODEX_ENV=(
    "PATH=$PATH"
    "HOME=$harness_home"
    "CODEX_HOME=$harness_home"
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
codex_exec() { # $@ the CLI and its arguments
  local seed="${LAB_CREDENTIAL_SEED:-}/$adapter_name/env"
  if [ -f "$seed" ]; then
    timeout "$timeout_s" env -i "${CODEX_ENV[@]}" \
      sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' _ "$seed" "$@"
  else
    timeout "$timeout_s" env -i "${CODEX_ENV[@]}" "$@"
  fi
}

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  require_tool codex || return 3
}

# Isolated CODEX_HOME with this checkout installed from a local marketplace —
# the same path `codex plugin add` takes for a real user.
adapter_install() { # $1 plugin source ("" = NONE arm, install nothing)
  harness_home="$(mktemp -d)"
  local f
  for f in auth.json config.toml models_cache.json; do
    [ -f "$source_codex_home/$f" ] && cp "$source_codex_home/$f" "$harness_home/$f"
  done
  codex_env
  # A copied config.toml can already register `augments-labs-dev` against the real
  # repo, which collides when this arm's source differs. Removed in the ISOLATED
  # home only — the user's own CODEX_HOME is never touched. On the NONE arm this
  # is the whole job: an isolated home with credentials and no plugin.
  env -i "${CODEX_ENV[@]}" codex plugin remove sdlc-skills >/dev/null 2>&1
  env -i "${CODEX_ENV[@]}" codex plugin marketplace remove augments-labs-dev >/dev/null 2>&1
  [ -n "$1" ] || return 0
  env -i "${CODEX_ENV[@]}" codex plugin marketplace add "$1" --json >/dev/null 2>>"$errlog" || {
    echo "marketplace add failed (see $errlog)" >&2; return 3; }
  env -i "${CODEX_ENV[@]}" codex plugin add sdlc-skills@augments-labs-dev --json >/dev/null 2>>"$errlog" || {
    echo "plugin add failed (see $errlog)" >&2; return 3; }
}

# Codex reads a skill as a shell command, so an activation is a command_execution
# that touches an installed SKILL.md.
adapter_chain() {
  jq -rc 'if (.type == "item.started" or .type == "item.completed")
             and .item.type == "command_execution" then
            (.item.command // "") as $cmd
            | ($cmd | scan("/skills/(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md")? | .[0])
            | if . == "" then empty else "sdlc-skills:" + . end
          else empty end' "$1" 2>/dev/null
}

adapter_behavioral_events() {
  jq -r 'if .type == "item.completed" and .item.type == "command_execution" then
           (.item.command // "") as $cmd
           | (($cmd | scan("/skills/(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md")? | .[0]) // "") as $skill
           | if $skill != "" then "SKILL sdlc-skills:" + $skill else empty end
         elif .type == "item.completed" and .item.type == "file_change" then
           .item.changes[]? | "EDIT " + (.path // "")
         else empty end' "$1" 2>/dev/null |
    awk '$0 != previous { print } { previous=$0 }'
}

# This harness needs the skill-instructions suffix to reach for a skill at all.
adapter_prompt_suffix() {
  printf '\n\nUse the relevant skill according to the skill instructions: read its SKILL.md completely before answering.'
}

adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream
  codex_env
  ( cd "$1" && codex_exec codex exec --json --ephemeral --skip-git-repo-check \
      -s read-only -C "$1" "$2" ) \
      < /dev/null > "$3" 2>>"$errlog"
}

adapter_activation_flags() { :; }

# DID IT RUN? A closed turn or a completed agent message means the model
# spoke; a provider that never answered emits neither. Without this the
# runner cannot tell a refusal from a miss, and a codex run that never
# reached the model was scored as an ordinary miss.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[];
      (.type == "turn.completed")
      or (.type == "item.completed" and .item.type == "agent_message"))' \
    >/dev/null 2>&1 <"$1"
}

# COST: one `turn.completed` closes a `codex exec` and carries the whole run's
# totals — 48k input tokens across several tool round-trips in the stream this
# was read from, not one model call's worth. Take the last such event.
#
# Add ONLY input + output. `cached_input_tokens` and `reasoning_output_tokens`
# are breakdowns *inside* those two, not extra charges: the probe reported 77
# reasoning tokens within 84 output tokens for a two-word reply. Summing all
# five fields would roughly double the number and quietly overstate what every
# skill costs.
adapter_usage() {
  jq -s 'map(select(.type == "turn.completed") | .usage) | last | select(. != null)
         | (.input_tokens // 0) + (.output_tokens // 0)' "$1" 2>/dev/null
}

# `-s workspace-write` replaces read-only so the agent can produce artifacts.
# Codex intentionally protects `.git` inside writable roots. Behavioural
# fixtures are disposable task branches whose local checkpoints are authorized,
# so automatic review supplies the supported, command-scoped path through that
# protection without removing the workspace sandbox.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  local prompt
  prompt="$(cat "$2")$(adapter_prompt_suffix)

This disposable behavioural run authorizes task-local Git checkpoint commits.
If the workspace sandbox protects Git metadata, request native permission
escalation for the exact Git command; that protection is not a denial of
checkpoint authority."
  ( cd "$1" && codex_exec codex exec --json --approve-for-me --skip-git-repo-check \
        -C "$1" "$prompt" ) \
      < /dev/null > "$3" 2>>"$errlog"
}

# Continue through the structured thread id emitted by `codex exec`. Resume
# inherits the original workspace and sandbox, but Codex does not retain the
# automatic approval reviewer across `exec resume`; bind it on every turn so
# protected Git checkpoints keep the same command-scoped review path.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" thread_id
  thread_id="$(jq -r 'select(.type == "thread.started") | .thread_id // empty' \
               "$prior" 2>/dev/null | head -1)"
  [ -n "$thread_id" ] || { echo "Codex stream contains no resumable thread id" >&2; return 2; }
  ( cd "$wd" && codex_exec codex exec resume --json --skip-git-repo-check \
        -c 'approval_policy="on-request"' \
        -c 'approvals_reviewer="auto_review"' \
        "$thread_id" "$prompt" \
    ) < /dev/null > "$out" 2>>"$errlog"
}