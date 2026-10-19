#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# pi CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `pi` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: documentation-grounded, runtime unverified.
#   - The flags come from pi 1.3.0's own shipped `--help` (docs/cli.md).
#   - The event protocol comes from pi 1.3.0's own shipped docs/json.md:
#     one JSON object per line, a `session` header first, then session
#     events, and `tool_execution_start` carrying `toolName` and `args`.
#   - How a skill is loaded comes from pi 1.3.0's docs/skills.md: the model
#     reads the skill's SKILL.md; pi binds no skill tool of its own. So the
#     structural skill-invocation record is a `read` tool call whose path is
#     a SKILL.md, and the skill's name is the directory above that file.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/pi/. No pi stream has been observed on
#     this machine, so every capability below is documentation, and
#     `runnable` stays `no` until a real run replaces the label.

adapter_name='pi'

runnable=no
runnable_reason="pi 1.3.0 is on PATH and its JSON event protocol is documented, but no pi run has been recorded on this machine"
# pi takes no approval flag; the permission-relevant flag this file passes is
# the tool allow-list, which decides what the run may touch at all.
permission_flags="--tools"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=no(documentation) post-compaction-event=no(documentation)"

source_pi_home="${PI_HOME:-${HOME:-}/.pi}"

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v pi >/dev/null 2>&1 || { echo "no \`pi\` CLI on PATH" >&2; return 3; }
}

# Isolated HOME: `pi install <path>` registers the checkout BY REFERENCE
# (measured upstream on 0.86.1: the throwaway home holds only
# `.pi/agent/settings.json` naming the checkout; nothing is copied), so the
# tree under test stays where the checkout is and `plugin_dir` names it.
# The NONE arm is an isolated home with no package registered at all.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  plugin_dir="$1"
  env -i PATH="$PATH" HOME="$harness_home" pi install "$1" </dev/null \
    >>"$errlog" 2>&1 || { echo "pi install failed (see $errlog)" >&2; return 1; }
  # The register line is the proof the install landed: a filesystem count of
  # the checkout cannot show that pi accepted the package.
  local listed
  listed="$(env -i PATH="$PATH" HOME="$harness_home" pi list </dev/null 2>>"$errlog")" || {
    echo "pi list failed (see $errlog)" >&2; return 1; }
  printf '%s\n' "$listed" | grep -F "$1" >/dev/null 2>&1 || {
    echo "pi list does not name the installed package (see $errlog)" >&2; return 1; }
  return 0
}

# The plugin comes from the registered package, not from a flag.
adapter_activation_flags() { :; }

# No suffix: pi's extension appends the router to the system prompt at
# session start, so the opening goes in bare, as a real user opening.
adapter_prompt_suffix() { :; }

# DETECTION: a `read` tool call whose path is a SKILL.md. pi binds no skill
# tool (docs/skills.md: "the model reads SKILL.md"), so the read of that file
# IS the structural skill-invocation record; the skill's name is the
# directory above it.
adapter_chain() { # $1 stream file (JSONL from --mode json)
  jq -r 'select(.type == "tool_execution_start")
         | select(.toolName == "read")
         | (.args.path // "") as $p
         | select($p | test("SKILL[.]md$"))
         | ($p | sub("/+$";"") | split("/") | .[-2] // empty)' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.type == "tool_execution_start")
         | (.toolName // "") as $t
         | (.args.path // "") as $p
         | if $t == "read" and ($p | test("SKILL[.]md$"))
           then "SKILL " + ($p | sub("/+$";"") | split("/") | .[-2] | tostring)
           elif ($t == "write" or $t == "edit")
           then "EDIT " + $p
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? An assistant `message_end` means the model spoke; docs/json.md
# makes `message_end` the authoritative final message. A dead provider emits
# none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .type == "message_end" and .message.role == "assistant")' \
    >/dev/null 2>&1 <"$1"
}

# COST: docs/json.md says the `usage` on a `message_update` is "the latest
# cumulative provider-reported usage for the assistant response", so the LAST
# update of a run carries the run's own total. A final message may also
# carry its own usage; it wins when it has one. Silent when neither is
# present, so a timed-out or refused run reports no number rather than a
# misleading zero.
adapter_usage() { # $1 stream file
  jq -s '([.[] | select(.type == "message_update") | .usage.totalTokens]
          | map(select(. != null)) | last) as $u
         | ([.[] | select(.type == "message_end" and .message.role == "assistant")
                | .message.usage.totalTokens]
            | map(select(. != null)) | last) as $m
         | if $u != null then $u elif $m != null then $m else empty end' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock. The tool
# allow-list keeps the arm read-only; the workdir is a disposable fixture
# and HOME is the throwaway run home.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  ( cd "$wd" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      pi --mode json --session-dir "$harness_home/sessions" \
         --tools read,grep,find,ls "$@" "$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  ( cd "$1" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      pi --mode json --session-dir "$harness_home/sessions" \
         --tools read,grep,find,ls,edit,write,bash "$(cat "$2")" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the prior
# stream's own `session` header (docs/json.md: `{"type":"session","id":...}`);
# an absent id is an adapter error, not a fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r 'select(.type == "session") | .id // empty' "$prior" 2>/dev/null \
    | head -1)"
  [ -n "$session_id" ] || { echo "pi stream contains no resumable session id" >&2; return 2; }
  ( cd "$wd" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      pi --mode json --session-dir "$harness_home/sessions" \
         --session "$session_id" \
         --tools read,grep,find,ls,edit,write,bash "$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}

# NO adapter_model: pi's --model takes a provider pattern, not a capability
# tier, and no official mapping from small/medium/large to a pi model exists.
# A scenario that asks for a tier is refused by the runner rather than run on
# the default model and called that tier.
