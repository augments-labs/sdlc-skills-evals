#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Grok Build CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `grok` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: documentation-grounded, runtime unverified.
#   - The install facts come from the pinned upstream's tests/harnesses/grok.sh
#     (upstream 638040d, v11.0.0): `grok plugin install <path> --trust` copies
#     the source recursively into a per-install directory under the throwaway
#     home, and HOME is overridden alongside GROK_HOME because grok
#     cross-reads a real `~/.claude/plugins/marketplaces/` whatever GROK_HOME
#     says. On 1.0.40 no hook reaches the prompt, so the routing channel is a
#     one-line rules file grok scans for every project.
#   - The flags come from grok 1.0.62's own `--help`: `-p` is the single-turn
#     prompt, `--output-format` takes plain | json | streaming-json |
#     streaming-messages-json, and `--permission-mode` takes default |
#     acceptEdits | auto | dontAsk | bypassPermissions | plan.
#   - The event protocol is the one grok's own help names:
#     `streaming-messages-json` is "NDJSON in the Anthropic Messages API wire
#     format" — the public Anthropic streaming protocol, whose records are
#     `message_start`, `content_block_start`, `content_block_delta`,
#     `content_block_stop`, `message_delta` and `message_stop`.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/grok/. No grok stream has been observed
#     on this machine, so every capability below is documentation and
#     `runnable` stays `no` until a real run replaces the label.

adapter_name='grok'

runnable=no
runnable_reason="grok 1.0.62 is on PATH and its streaming-messages-json format is documented by the CLI itself, but no grok run has been recorded on this machine"
permission_flags="--permission-mode acceptEdits"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=no(documentation) post-compaction-event=no(documentation)"

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v grok >/dev/null 2>&1 || { echo "no \`grok\` CLI on PATH" >&2; return 3; }
}

# Isolated home, installed the way `grok plugin install <path> --trust`
# installs it for a real user: offline and without login, since a local-path
# source is copied on the filesystem without touching the network.
#
# HOME is overridden alongside GROK_HOME, not GROK_HOME alone: grok
# cross-reads a real `~/.claude/plugins/marketplaces/` for Claude-compatible
# plugins regardless of GROK_HOME, so on an operator who already has
# sdlc-skills installed for Claude Code, GROK_HOME isolation alone would let
# that install answer for the tree under test.
#
# `grok plugin install` COPIES the source rather than loading the checkout in
# place, so `plugin_dir` is recorded as the checkout for `cd` purposes only.
#
# The NONE arm is an isolated home with no plugin and no rules file: the
# nudge is the routing channel, and the none arm must carry none.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  plugin_dir="$1"
  env -i PATH="$PATH" HOME="$harness_home" GROK_HOME="$harness_home" \
    grok plugin install "$1" --trust </dev/null >>"$errlog" 2>&1 || {
    echo "grok plugin install failed (see $errlog)" >&2; return 1; }

  # RULES-FILE PROBE: no hook on 1.0.40 reaches the prompt, so the one
  # channel that nudges the router is a rules file grok scans regardless of
  # folder trust. Write the same one-line nudge a real install needs, then
  # read it straight back through `grok inspect --json`'s own
  # `projectInstructions` array in this same isolated home. No model turn.
  local out instructions
  mkdir -p "$harness_home/rules"
  printf 'Invoke the `using-sdlc-skills` skill before acting.\n' \
    >"$harness_home/rules/using-sdlc-skills.md"
  out="$(cd "$plugin_dir" && env -i PATH="$PATH" HOME="$harness_home" GROK_HOME="$harness_home" \
    grok inspect --json </dev/null 2>>"$errlog")" || {
    echo "grok inspect failed (see $errlog)" >&2; return 1; }
  instructions="$(jq -c '.projectInstructions' <<<"$out" 2>>"$errlog")" || {
    echo "grok inspect output did not parse (see $errlog)" >&2; return 1; }
  jq -e '.[] | select((.path | endswith("rules/using-sdlc-skills.md")) and .scope == "global")' \
    <<<"$instructions" >/dev/null 2>>"$errlog" || {
    echo "grok inspect did not list the rules-file nudge (see $errlog)" >&2; return 1; }
  return 0
}

# The plugin comes from the installed plugin set, not from a flag.
adapter_activation_flags() { :; }

# No suffix: grok's rules file is the routing channel, so the opening goes
# in bare, as a real user opening.
adapter_prompt_suffix() { :; }

# DETECTION: a `content_block_start` whose block is a `tool_use` for the
# skill tool. In the Anthropic wire format the tool's arguments arrive as
# `input_json_delta` fragments, so the fragments of a block are joined
# before the argument object is read.
adapter_chain() { # $1 stream file (JSONL from --output-format streaming-messages-json)
  jq -sr '
    ( [ .[] | select(.type == "content_block_delta" and .delta.type == "input_json_delta")
          | {index: (.index | tostring), p: (.delta.partial_json // "")} ]
      | reduce .[] as $d ({}; .[$d.index] = ((.[$d.index] // "") + $d.p)) ) as $parts
    | [ .[] | select(.type == "content_block_start" and .content_block.type == "tool_use")
          | {index: (.index | tostring), name: (.content_block.name // ""),
             args: (.content_block.input // {})} ]
    | .[]
    | select((.name | ascii_downcase) | test("skill"))
    | ( (($parts[.index] // "") | (try fromjson catch {})) ) as $parsed
    | ((.args // {}) + $parsed) as $in
    | ($in.skill // $in.name // "")' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -sr '
    ( [ .[] | select(.type == "content_block_delta" and .delta.type == "input_json_delta")
          | {index: (.index | tostring), p: (.delta.partial_json // "")} ]
      | reduce .[] as $d ({}; .[$d.index] = ((.[$d.index] // "") + $d.p)) ) as $parts
    | [ .[] | select(.type == "content_block_start")
          | {index: (.index | tostring), type: (.content_block.type // ""),
             name: (.content_block.name // ""), args: (.content_block.input // {})} ]
    | .[]
    | ( (($parts[.index] // "") | (try fromjson catch {})) ) as $parsed
    | ((.args // {}) + $parsed) as $in
    | if ((.name | ascii_downcase) | test("skill")) and ($in.skill != null)
      then "SKILL " + ($in.skill | tostring)
      elif (.type == "tool_use") and ($in.file_path != null)
      then "EDIT " + ($in.file_path | tostring)
      elif (.type == "tool_use") and ($in.path != null)
      then "EDIT " + ($in.path | tostring)
      else empty end' "$1" 2>/dev/null
}

# DID IT RUN? `message_start` is the Anthropic protocol's first record for a
# model response; a dead provider emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .type == "message_start")' >/dev/null 2>&1 <"$1"
}

# COST: the Anthropic wire format carries the prompt's tokens on
# `message_start.message.usage.input_tokens` and the completion's on
# `message_delta.usage.output_tokens`. Both are added. Silent when neither
# is present, so a timed-out or refused run reports no number rather than a
# misleading zero.
adapter_usage() { # $1 stream file
  jq -s '([.[] | select(.type == "message_start") | .message.usage.input_tokens]
          | map(select(. != null)) | last) as $in
         | ([.[] | select(.type == "message_delta") | .usage.output_tokens]
            | map(select(. != null)) | last) as $out
         | if $in != null or $out != null
           then (($in // 0) + ($out // 0))
           else empty end' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock. `--permission-mode
# plan` keeps the arm read-only; the workdir is a disposable fixture and
# HOME is the throwaway run home.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  ( cd "$wd" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      GROK_HOME="$harness_home" TMPDIR="${TMPDIR:-/tmp}" \
      grok -p "$prompt" --output-format streaming-messages-json \
        --permission-mode plan --cwd "$wd" "$@" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  ( cd "$1" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      GROK_HOME="$harness_home" TMPDIR="${TMPDIR:-/tmp}" \
      grok -p "$(cat "$2")" --output-format streaming-messages-json \
        --permission-mode acceptEdits --cwd "$1" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# NO adapter_continue_behavioral: the Anthropic wire format carries a
# message id, not a session id, and grok's `--continue` would pick a session
# by directory rather than by evidence from the prior stream — which the
# contract forbids ("resume from structured session evidence, never a fresh
# session"). A scenario with follow-up turns is refused by the runner on this
# adapter rather than answered by a session the run did not prove.
#
# NO adapter_model: grok's `--model` takes a model id and its own catalogue;
# no official small/medium/large mapping exists. A scenario that asks for a
# tier is refused by the runner rather than run on the default model and
# called that tier.
