#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Hermes Agent adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `hermes` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: documentation-grounded, runtime unverified.
#   - The install facts come from the pinned upstream's tests/harnesses/hermes.sh
#     (upstream 638040d, v11.0.0): `hermes plugins install <repo> --enable`
#     refuses a bare path and clones the HEAD of a git source, so the
#     working tree is snapshotted into a throwaway repository first; the
#     plugin lands under $HERMES_HOME/plugins/sdlc-skills.
#   - The event protocol comes from hermes' own source at v0.21.7
#     (hermes_cli/stream_json.py): `hermes chat -q ... --format stream-json`
#     writes one JSON object per line — `system`/`init`, `text` deltas,
#     `tool_use`, `tool_result`, and one terminal `result` envelope carrying
#     the token counts. The module's own docstring states the protocol.
#   - The skill tool is hermes' `skill_view` (hermes 0.21.7: the tool names
#     are in agent/system_prompt.py and agent/display.py), and the upstream
#     records that hermes lists a plugin skill as `sdlc-skills:<name>`.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/hermes/. No hermes stream has been
#     observed on this machine — the local install cannot even print
#     `--help` ("no dependency environment is committed for this install") —
#     so every capability below is documentation and `runnable` stays `no`.
#
# LIMIT, stated rather than worked around: hermes needs its Python
# environment once per throwaway home, and that fetch is a network call. The
# adapter therefore never runs `hermes` on its own account; a run must be
# launched by the operator, who accepts that one download.
#
# ISOLATION. Every invocation of the CLI runs under an environment this file
# builds explicitly (hermes_env): the throwaway home, the CLI's own
# HERMES_HOME — which is where the plugin lands and where hermes syncs its
# Python environment — the XDG directories inside the throwaway home, a
# runtime directory and a dead session-bus socket inside it. The operator's
# environment is NOT inherited: it carries the operator's own session bus,
# their SSH agent, their IDE tokens and their credential helpers, and an
# invocation that inherited them could read the operator's stored
# credentials. The one exception is the operator's credential seed
# ($LAB_CREDENTIAL_SEED/hermes/env), which the runner exports for a harness
# whose auth is environmental: it is sourced INSIDE the child process, so
# its values reach the CLI and never reach a command line, a log or this
# shell.

adapter_name='hermes'

runnable=no
runnable_reason="hermes 0.21.7 is on PATH and its stream-json protocol is documented in its own source, but the local install has no committed dependency environment and no hermes run has been recorded on this machine"
# hermes takes no approval flag on the CLI; the permission-relevant flag
# this file passes is the tool allow-list, which decides what the run may
# touch at all.
permission_flags="--tools"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=yes(documentation) post-compaction-event=yes(documentation)"

source_hermes_home="${HERMES_HOME:-${HOME:-}/.hermes}"

# THE LAUNCH ENVIRONMENT, built explicitly (see the header).
hermes_env() {
  HERMES_ENV=(
    "PATH=$PATH"
    "HOME=$harness_home"
    "HERMES_HOME=$harness_home"
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
hermes_exec() { # $@ the CLI and its arguments
  local seed="${LAB_CREDENTIAL_SEED:-}/$adapter_name/env"
  if [ -f "$seed" ]; then
    timeout "$timeout_s" env -i "${HERMES_ENV[@]}" \
      sh -c 'set -a; . "$1"; set +a; shift; exec "$@"' _ "$seed" "$@"
  else
    timeout "$timeout_s" env -i "${HERMES_ENV[@]}" "$@"
  fi
}

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v hermes >/dev/null 2>&1 || { echo "no \`hermes\` CLI on PATH" >&2; return 3; }
}

# Isolated HOME and HERMES_HOME: a HERMES_HOME outside ~/.hermes is its own
# data root, and hermes syncs a Python environment into it on first launch.
# HOME is overridden alongside it so nothing reads the operator's home.
#
# `hermes plugins install` refuses a bare path and CLONES the HEAD of a git
# source, so a file:// URL to the checkout would test the last commit rather
# than the tree under test. The working tree is snapshotted into a throwaway
# repository named sdlc-skills first, and that snapshot is what gets
# installed — hermes names the install after the repo when the root carries
# no manifest.
#
# The NONE arm is an isolated home with no plugin installed.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  local snap="$harness_home/src/sdlc-skills"
  mkdir -p "$snap"
  ( cd "$1" && git ls-files -z --cached --others --exclude-standard |
      while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done |
      tar --null -T - -cf - ) | tar -x -C "$snap" 2>>"$errlog" || {
    echo "could not snapshot $1 (see $errlog)" >&2; return 1; }
  git -C "$snap" init -q >>"$errlog" 2>&1 &&
    git -C "$snap" add -A >>"$errlog" 2>&1 &&
    git -C "$snap" -c user.name=sdlc-skills-evals -c user.email=evals@example.invalid \
      commit -qm snapshot >>"$errlog" 2>&1 || {
    echo "could not commit the snapshot (see $errlog)" >&2; return 1; }
  hermes_env
  env -i "${HERMES_ENV[@]}" \
    hermes plugins install "file://$snap" --enable --yes-deps \
    </dev/null >>"$errlog" 2>&1 || {
    echo "hermes plugins install failed (see $errlog)" >&2; return 1; }
  plugin_dir="$harness_home/plugins/sdlc-skills"
  return 0
}

# The plugin comes from the installed plugin set, not from a flag.
adapter_activation_flags() { :; }

# No suffix: hermes renders the router into the session's system prompt as
# plugin sections, so the opening goes in bare.
adapter_prompt_suffix() { :; }

# DETECTION: a `tool_use` record naming hermes' skill tool. The upstream
# records that hermes lists a plugin skill as `sdlc-skills:<name>`, so the
# name is reported as hermes names it and the runner normalizes the prefix.
adapter_chain() { # $1 stream file (JSONL from --format stream-json)
  jq -r 'select(.type == "tool_use")
         | select(.name == "skill_view")
         | (.input.name // .input.skill // empty)' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.type == "tool_use")
         | (.name // "") as $n
         | (.input // {}) as $i
         | if $n == "skill_view"
           then "SKILL " + ($i.name // $i.skill // "")
           elif ($n == "write_file" or $n == "edit_file" or $n == "str_replace")
           then "EDIT " + ($i.path // $i.file_path // "")
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? The terminal `result` envelope is hermes' own close of a run
# (hermes_cli/stream_json.py: "one terminal `result` envelope"). A dead
# provider emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .type == "result")' >/dev/null 2>&1 <"$1"
}

# COST: the terminal `result` envelope carries the run's own token counts
# under `tokens` (input, output, total, cache_read, cache_write). The
# explicit total wins; otherwise input + output are added. Silent when no
# result envelope arrives, so a timed-out or refused run reports no number
# rather than a misleading zero.
adapter_usage() { # $1 stream file
  jq -s 'map(select(.type == "result") | .tokens) | last | select(. != null)
         | .total // ((.input // 0) + (.output // 0))' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock. The tool
# allow-list keeps the arm read-only.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  hermes_env
  ( cd "$wd" && hermes_exec hermes chat -q "$prompt" --format stream-json \
        --tools read_file,search_files,grep,skill_view,skills_list "$@" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  hermes_env
  ( cd "$1" && hermes_exec hermes chat -q "$(cat "$2")" --format stream-json \
        --tools read_file,search_files,grep,write_file,edit_file,str_replace,skill_view,skills_list ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the prior
# stream's own `system`/`init` record; an absent id is an adapter error, not
# a fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r 'select(.type == "system" and .subtype == "init")
                       | .session_id // empty' "$prior" 2>/dev/null | head -1)"
  [ -n "$session_id" ] || { echo "hermes stream contains no resumable session id" >&2; return 2; }
  hermes_env
  ( cd "$wd" && hermes_exec hermes chat -q "$prompt" --format stream-json --resume "$session_id" \
        --tools read_file,search_files,grep,write_file,edit_file,str_replace,skill_view,skills_list ) \
    < /dev/null > "$out" 2>>"$errlog"
}

# NO adapter_model: hermes binds a model per provider and its own reasoning
# levels; no official small/medium/large mapping exists. A scenario that asks
# for a tier is refused by the runner rather than run on the default model
# and called that tier.
