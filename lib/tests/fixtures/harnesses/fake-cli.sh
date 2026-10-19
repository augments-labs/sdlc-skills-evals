#!/usr/bin/env bash
# Fake CLI for the adapter contract tests. NEVER a model of any CLI's
# behaviour: it records every invocation and answers the install commands
# the adapters drive, so a test can prove what the adapter asked for.
#
# One file serves every CLI: the test copies it to <name> in a throwaway bin
# directory and this script dispatches on the name it was invoked as. The
# invocation log is the sentinel — the real CLIs are not on the test's PATH,
# so an adapter that reaches one fails instead of launching it.
#
# The log goes to $FAKE_HARNESS_LOG when the environment carries it, and to
# $HOME/.fake-harness.log when it does not: several adapters launch their CLI
# with a cleared environment (HOME only), and the log has to survive that.
#
# Three records per invocation, so a test can PROVE which binary answered and
# what it was handed:
#   call <name> <args>   — the invocation itself
#   at   <name> <path>   — the resolved path of this binary, so the log shows
#                          the fake answered and not a real CLI
#   env  <name> KEY=VAL  — the environment the CLI was launched with, one
#                          variable per line (so a value with spaces stays
#                          readable)
set -uo pipefail

self="$(basename "$0")"
_log="${FAKE_HARNESS_LOG:-}"
[ -n "$_log" ] || { [ -n "${HOME:-}" ] && _log="$HOME/.fake-harness.log"; }
if [ -n "$_log" ]; then
  printf 'call %s %s\n' "$self" "$*" >> "$_log" 2>/dev/null || true
  printf 'at %s %s\n' "$self" "$0" >> "$_log" 2>/dev/null || true
  env | sort | sed "s/^/env $self /" >> "$_log" 2>/dev/null || true
fi

_state="${HOME:-}/.fake-state"
[ -n "${HOME:-}" ] || _state=""

# --- version ------------------------------------------------------------------
case "${1:-}" in
  --version|-v|-V)
    printf '%s %s\n' "$self" "${FAKE_VERSION:-1.0.0}"
    exit 0
    ;;
esac

# --- per-CLI install and inspection commands ----------------------------------
case "$self" in
  agy)
    if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "install" ]; then
      src="${3:-}"; dest="${HOME:-}/.gemini/config/plugins/sdlc-skills"
      mkdir -p "$dest" 2>/dev/null
      [ -d "$src" ] && ( cd "$src" && tar --exclude=.git -cf - . ) 2>/dev/null | tar -xf - -C "$dest" 2>/dev/null
      exit 0
    fi
    ;;
  codex)
    case "${1:-} ${2:-}" in
      "plugin marketplace"|"plugin add"|"plugin remove")
        exit 0
        ;;
    esac
    ;;
  devin)
    if [ "${1:-}" = "plugins" ] && [ "${2:-}" = "install" ]; then exit 0; fi
    case " $* " in
      *" acp "*)
    # A minimal ACP server: answer initialize, open a session, run the
    # prompt. The agent's own notifications are the recorded stream.
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*)
          printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":false},"authMethods":[]}}\n'
          ;;
        *'"method":"session/new"'*)
          printf '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"sess-fake-acp-1"}}\n'
          ;;
        *'"method":"session/prompt"'*)
          printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-fake-acp-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ok"}}}}\n'
          printf '{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}\n'
          ;;
      esac
    done
    exit 0
    ;;
    esac
    ;;
  grok)
    if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "install" ]; then exit 0; fi
    if [ "${1:-}" = "inspect" ]; then
      printf '{"projectInstructions":[{"path":"%s/rules/using-sdlc-skills.md","scope":"global"}],"skills":[]}\n' \
        "${HOME:-}"
      exit 0
    fi
    ;;
  hermes)
    if [ "${1:-}" = "plugins" ] && [ "${2:-}" = "install" ]; then
      mkdir -p "${HOME:-}/plugins/sdlc-skills" 2>/dev/null
      exit 0
    fi
    if [ "${1:-}" = "prompt-size" ]; then
      printf '{"skills_breakdown":[{"name":"sdlc-skills:using-sdlc-skills"}]}\n'
      exit 0
    fi
    ;;
  muse)
    if [ "${1:-}" = "skills" ] && [ "${2:-}" = "install" ]; then
      src="${3:-}"; name="$(basename "$src")"
      dest="${XDG_CONFIG_HOME:-${HOME:-}/.config}/muse/skills/$name"
      mkdir -p "$dest" 2>/dev/null
      [ -d "$src" ] && ( cd "$src" && tar --exclude=.git -cf - . ) 2>/dev/null | tar -xf - -C "$dest" 2>/dev/null
      printf '{}\n'
      exit 0
    fi
    ;;
  pi)
    if [ "${1:-}" = "install" ]; then
      [ -n "$_state" ] && mkdir -p "$_state" 2>/dev/null
      [ -n "$_state" ] && printf '%s\n' "${2:-}" > "$_state/pi-installed"
      exit 0
    fi
    if [ "${1:-}" = "list" ]; then
      [ -n "$_state" ] && [ -f "$_state/pi-installed" ] && cat "$_state/pi-installed"
      exit 0
    fi
    ;;
esac

# --- the run itself ----------------------------------------------------------
# The fake never speaks for a CLI's output format; the stream a test parses
# comes from the labelled synthetic fixture, not from here. What the fake
# contributes is the proof that the adapter reached a CLI, with which flags.
#
# The stdout file is read from $FAKE_STDOUT when the environment carries it
# and from $HOME/.fake-stdout when it does not: several adapters launch their
# CLI with a cleared environment (HOME only).
_out="${FAKE_STDOUT:-}"
[ -n "$_out" ] || { [ -n "${HOME:-}" ] && _out="$HOME/.fake-stdout"; }
if [ -n "$_out" ] && [ -f "$_out" ]; then
  cat "$_out"
else
  # Always something on stdout, so a test can tell that the adapter piped
  # the CLI's output into the stream file.
  printf 'fake-cli %s\n' "$self"
fi
exit 0
