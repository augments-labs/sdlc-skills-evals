#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Antigravity CLI (`agy`) adapter. Sourced by the runners — never executed
# directly.
#
# This file holds only what is true of the `agy` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: observed envelope, runtime unverified.
#   - The install facts come from the pinned upstream's
#     tests/harnesses/antigravity.sh (upstream 638040d, v11.0.0): agy installs
#     `plugins/sdlc-skills/` — the Codex plugin directory — and copies it into
#     `~/.gemini/config/plugins/sdlc-skills/`; a local install needs no
#     sign-in and no network.
#   - The print-mode envelope was OBSERVED on agy 1.4.0 on this machine with
#     `agy --print='<prompt>' --output-format stream-json`: an `init` record
#     carrying `conversation_id` and the tool list, `step_update` records
#     carrying `step_index`, `state`, `step_type`, `text_delta` and `usage`,
#     and a terminal `result` record carrying `status` and `usage`. The
#     `conversation_id` on every record is the structured session evidence
#     the resume path uses.
#   - A skill-invocation record is NOT covered by that observation: the
#     observed run made no tool call. The record shape used here is the CLI's
#     OWN output-event struct, whose tags are `skill_name` and `tool_name`
#     (the `localagentcore.OutputEvent` type in the agy 1.4.0 binary), and a
#     tool call whose argument path is a SKILL.md. That part is
#     documentation-grounded, not observed.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/antigravity/. No skill-loading run has
#     been recorded on this machine, so `runnable` stays `no` until a real
#     run replaces the label.

adapter_name='antigravity'

runnable=no
runnable_reason="agy 1.4.0 is on PATH and its print-mode envelope was observed here, but no skill-loading run has been recorded on this machine"
permission_flags="--mode accept-edits"
capabilities="subagent-loads-skills=unknown(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=no(documentation) post-compaction-event=no(documentation)"

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v agy >/dev/null 2>&1 || { echo "no \`agy\` CLI on PATH" >&2; return 3; }
}

# Isolated HOME, because `agy plugin install` writes into `~/.gemini/config/`.
# Antigravity installs plugins/sdlc-skills/, the Codex plugin directory, not
# the checkout root: it loads skills one level deep, which the flat mirror
# there satisfies, and the root's AGENTS.md and GEMINI.md would load as
# rules.
#
# The plugin's always-on rule is the routing channel on this CLI — the
# upstream records that antigravity runs no session-start hook from a plugin
# — so its presence in the installed copy is checked here: a plugin that
# installed without its rule would load no router.
#
# The NONE arm is an isolated home with no plugin installed.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  [ -n "${1:-}" ] || return 0
  ( cd "$harness_home" && HOME="$harness_home" agy plugin install "$1/plugins/sdlc-skills" \
      </dev/null ) >>"$errlog" 2>&1 || {
    echo "agy plugin install failed (see $errlog)" >&2; return 1; }
  local installed="$harness_home/.gemini/config/plugins/sdlc-skills"
  [ -f "$installed/rules/AGENTS.md" ] || {
    echo "no rules/AGENTS.md in the installed plugin — the router nudge would not load (see $errlog)" >&2
    return 1; }
  plugin_dir="$installed"
  return 0
}

# The plugin comes from the installed plugin set, not from a flag.
adapter_activation_flags() { :; }

# No suffix: the plugin's always-on rule is the routing channel, so the
# opening goes in bare, as a real user opening.
adapter_prompt_suffix() { :; }

# DETECTION: a `step_update` carrying a skill name, or a tool call whose
# argument path is a SKILL.md. The skill's name is the directory above that
# file.
adapter_chain() { # $1 stream file (JSONL from --output-format stream-json)
  jq -r 'select(.event == "step_update")
         | (.step_update // {}) as $s
         | ($s.skill_name // empty),
           ( ($s.tool_name // "") as $t
             | select($t | test("view_file|read_file"))
             | (($s.path // $s.args.path // $s.arguments.path // $s.file_path // "") // "") as $p
             | select($p | test("SKILL[.]md$"))
             | ($p | sub("/+$";"") | split("/") | .[-2]) )' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.event == "step_update")
         | (.step_update // {}) as $s
         | ($s.skill_name // empty) as $sn
         | if $sn != "" then "SKILL " + ($sn | tostring)
           else ( ($s.tool_name // "") as $t
             | (($s.path // $s.args.path // $s.arguments.path // $s.file_path // "") // "") as $p
             | if ($t | test("view_file|read_file")) and ($p | test("SKILL[.]md$"))
               then "SKILL " + ($p | sub("/+$";"") | split("/") | .[-2] | tostring)
               elif ($t | test("write_to_file|replace_file_content|sed_file"))
               then "EDIT " + $p
               else empty end ) end' "$1" 2>/dev/null
}

# DID IT RUN? An agent response step or the terminal result record means the
# model spoke; a dead provider emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .event == "result"
                   or (.event == "step_update" and .step_update.step_type == "agent_response"))' \
    >/dev/null 2>&1 <"$1"
}

# COST: the observed envelope carries the run's own totals under `usage`
# (`input_tokens`, `output_tokens`, `thinking_tokens`, `cache_read_tokens`,
# `total_tokens`) on the last step and on the result record. The explicit
# total wins. Silent when no usage is present, so a timed-out or refused run
# reports no number rather than a misleading zero.
adapter_usage() { # $1 stream file
  jq -s '([.[] | (.result.usage.total_tokens? // .step_update.usage.total_tokens?)]
          | map(select(. != null)) | last) // empty' "$1" 2>/dev/null
}

# Activation probe: one query, bounded by the wall clock. `--mode plan` is
# antigravity's read-only execution mode; the workdir is a disposable
# fixture and HOME is the throwaway run home.
#
# `--print` takes the prompt AS ITS VALUE: a space-separated `--print` takes
# the next flag as its prompt (agy 1.4.0 says so itself), so the prompt is
# attached.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  ( cd "$wd" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      agy --output-format stream-json --mode plan "$@" --print="$prompt" ) \
    < /dev/null > "$stream" 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  ( cd "$1" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      agy --output-format stream-json --mode accept-edits --print="$(cat "$2")" ) \
    < /dev/null > "$3" 2>>"$errlog"
}

# Continue the same behavioural session. The conversation id comes from the
# prior stream's own records — every record of the observed envelope carries
# it — and is handed back with `--conversation`. An absent id is an adapter
# error, not a fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" conversation_id
  conversation_id="$(jq -r 'select(.conversation_id? != null) | .conversation_id' \
    "$prior" 2>/dev/null | head -1)"
  [ -n "$conversation_id" ] || { echo "Antigravity stream contains no resumable conversation id" >&2; return 2; }
  ( cd "$wd" && exec timeout "$timeout_s" env -i PATH="$PATH" HOME="$harness_home" \
      TMPDIR="${TMPDIR:-/tmp}" \
      agy --output-format stream-json --mode accept-edits \
        --conversation "$conversation_id" --print="$prompt" ) \
    < /dev/null > "$out" 2>>"$errlog"
}

# NO adapter_model: agy takes `--model` and `--effort`, but no official
# small/medium/large mapping exists. A scenario that asks for a tier is
# refused by the runner rather than run on the default model and called that
# tier.
