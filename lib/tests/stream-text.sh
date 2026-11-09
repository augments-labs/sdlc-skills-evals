#!/usr/bin/env bash
# Offline test: lib/stream-text.sh — the assistant text a run's stream
# carries, for every harness envelope the lab launches.
#
# Each case starts from the committed activation fixture of one harness
# (lib/tests/fixtures/harnesses/<h>/activation.json, a JSON array turned
# into the NDJSON stream the adapter writes) and appends records in that
# same envelope, so the extractor is read against the real record mix:
# tool calls, usage, deltas and terminal summaries side by side. Nothing
# here launches a CLI.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fix="$here/lib/tests/fixtures/harnesses"
# shellcheck source=lib/stream-text.sh
. "$here/lib/stream-text.sh" 2>/dev/null || true

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

type lab_extract_stream_text >/dev/null 2>&1 \
  && ok "lib/stream-text.sh defines lab_extract_stream_text" \
  || bad "lib/stream-text.sh defines lab_extract_stream_text"

stream_of() { # $1 harness $2.. extra NDJSON records — prints the stream path
  local h="$1" s="$work/$1.$RANDOM.ndjson"; shift
  jq -c '.[]' "$fix/$h/activation.json" > "$s"
  local r
  for r in "$@"; do printf '%s\n' "$r" >> "$s"; done
  printf '%s' "$s"
}

expect_text() { # $1 label $2 stream $3 harness-or-empty $4 expected
  local got rc
  if [ -n "$3" ]; then got="$(lab_extract_stream_text "$2" "$3" 2>/dev/null)"; rc=$?
  else got="$(lab_extract_stream_text "$2" 2>/dev/null)"; rc=$?; fi
  if [ "$rc" -eq 0 ] && [ "$got" = "$4" ]; then ok "$1"
  else bad "$1 (exit $rc, got '$got', want '$4')"; fi
}

expect_none() { # $1 label $2 stream $3 harness — no text, non-zero exit
  local got rc
  got="$(lab_extract_stream_text "$2" "$3" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$got" ]; then ok "$1"
  else bad "$1 (exit $rc, got '$got')"; fi
}

# --- every harness: the fixture plus a later answer in its own envelope ------
#
# The expected text is the LAST answer the stream carries: a terminal
# summary where the envelope has one, else the last whole assistant
# message, else the deltas joined. The fixture's earlier text must not
# leak into it.

declare -A extra want
extra[antigravity]='{"event":"step_update","step_update":{"conversation_id":"conv-antigravity-1","step_index":4,"state":"ACTIVE","step_type":"agent_response","text_delta":"final "}}
{"event":"step_update","step_update":{"conversation_id":"conv-antigravity-1","step_index":5,"state":"DONE","step_type":"agent_response","text_delta":"antigravity"}}
{"event":"result","result":{"conversation_id":"conv-antigravity-1","status":"SUCCESS","response":"final antigravity"}}'
want[antigravity]='final antigravity'
extra[claude-code]='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"draft claude"}]},"session_id":"sess-claude-1"}
{"type":"result","subtype":"success","is_error":false,"result":"final claude","session_id":"sess-claude-1"}'
want[claude-code]='final claude'
extra[codex]='{"type":"item.completed","item":{"id":"item-3","type":"reasoning","text":"thinking codex"}}
{"type":"item.completed","item":{"id":"item-4","type":"agent_message","text":"final codex"}}'
want[codex]='final codex'
extra[cursor]='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"draft cursor"}]},"session_id":"sess-cursor-1","timestamp_ms":5}
{"type":"result","subtype":"success","is_error":false,"result":"final cursor","session_id":"sess-cursor-1"}'
want[cursor]='final cursor'
extra[devin]='{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-devin-1","update":{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"thinking devin"}}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-devin-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":" / final "}}}}
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-devin-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"devin"}}}}'
want[devin]='loading / final devin'
extra[grok]='{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}
{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"final "}}
{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"grok"}}
{"type":"content_block_stop","index":1}'
want[grok]='final grok'
extra[hermes]='{"type":"text","text":"draft hermes"}
{"type":"result","session_id":"sess-hermes-1","exit_code":0,"text":"final hermes"}'
want[hermes]='final hermes'
extra[kimi-code]='{"role":"tool","content":"tool output kimi","tool_call_id":"call-1"}
{"role":"assistant","content":[{"type":"text","text":"final kimi"}]}'
want[kimi-code]='final kimi'
extra[muse]='{"schema_version":1,"id":"r-6","stream":{"kind":"session","id":"sess-muse-1"},"sequence":5,"recorded_at":6,"record_type":"status","durability":"ephemeral","causation_id":"c-2","payload_type":"run.output.delta","payload_schema_version":1,"payload":{"kind":"run_output_delta","text":"final "}}
{"schema_version":1,"id":"r-7","stream":{"kind":"session","id":"sess-muse-1"},"sequence":6,"recorded_at":7,"record_type":"event","durability":"durable","causation_id":"c-2","payload_type":"run.terminal.completed","payload_schema_version":1,"payload":{"kind":"run_terminal","terminal":"completed","text":"final muse"}}'
want[muse]='final muse'
extra[opencode]='{"type":"text","timestamp":6,"sessionID":"ses_test","part":{"id":"p6","messageID":"m2","sessionID":"ses_test","type":"text","text":"final opencode"}}'
want[opencode]='final opencode'
extra[pi]='{"type":"message_start","message":{"role":"assistant","content":[],"stopReason":"pending"}}
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"final "}}
{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"pi"}}
{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"final pi"}],"stopReason":"stop"}}'
want[pi]='final pi'

harnesses=(antigravity claude-code codex cursor devin grok hermes kimi-code muse opencode pi)
[ "$(find "$fix" -mindepth 2 -maxdepth 2 -name activation.json | wc -l)" -eq "${#harnesses[@]}" ] \
  && ok "every committed activation fixture is covered" \
  || bad "every committed activation fixture is covered"

for h in "${harnesses[@]}"; do
  mapfile -t recs <<<"${extra[$h]}"
  s="$(stream_of "$h" "${recs[@]}")"
  expect_text "$h: the last answer, named harness" "$s" "$h" "${want[$h]}"
  expect_text "$h: the last answer, shape alone" "$s" "" "${want[$h]}"
done

# --- the committed fixtures as they stand ------------------------------------
#
# A stream with a terminal summary AND the deltas that built it yields the
# summary once — never the deltas glued in front of it.

expect_text "antigravity: the result, not the deltas before it" \
  "$(stream_of antigravity)" antigravity "done"
expect_text "muse: the terminal record, not the delta before it" \
  "$(stream_of muse)" muse "loaded"
expect_text "pi: the finished message, not its deltas again" \
  "$(stream_of pi)" pi "loading loaded"
expect_text "claude-code: the result, once" "$(stream_of claude-code)" claude-code "loaded"
expect_text "hermes: the result record's text, once" "$(stream_of hermes)" hermes "loaded"
expect_text "opencode: the text part" "$(stream_of opencode)" opencode "looking at the plan"
expect_text "kimi-code: the last assistant message" "$(stream_of kimi-code)" kimi-code "loaded"
expect_text "cursor: the last assistant message" "$(stream_of cursor)" cursor "loaded"
expect_text "devin: the message chunks" "$(stream_of devin)" devin "loading"

# a stream whose text is only a tool's input is not an answer
expect_none "codex: a command's output is not assistant text" "$(stream_of codex)" codex
expect_none "grok: tool input JSON is not assistant text" "$(stream_of grok)" grok

# --- .type == "text": hermes and opencode share a type name ------------------
#
# hermes carries the text at the top level; opencode inside .part. Read
# as the other harness, neither yields text; read by shape alone, each
# yields its own.

h_only="$work/hermes-only.ndjson"
printf '%s\n' '{"type":"text","text":"hermes words"}' > "$h_only"
o_only="$work/opencode-only.ndjson"
printf '%s\n' '{"type":"text","sessionID":"s","part":{"id":"p1","type":"text","text":"opencode words"}}' > "$o_only"
expect_none "hermes text read as opencode yields nothing" "$h_only" opencode
expect_none "opencode text read as hermes yields nothing" "$o_only" hermes
expect_text "hermes text by shape" "$h_only" "" "hermes words"
expect_text "opencode text by shape" "$o_only" "" "opencode words"

# an opencode part re-emitted under the same id is one message, not two
dup="$work/opencode-dup.ndjson"
printf '%s\n' \
  '{"type":"text","part":{"id":"p9","type":"text","text":"same part"}}' \
  '{"type":"text","part":{"id":"p9","type":"text","text":"same part"}}' > "$dup"
expect_text "opencode: a re-emitted part is not duplicated" "$dup" opencode "same part"

# --- multi-line answers survive ----------------------------------------------
ml="$work/claude-multiline.ndjson"
printf '%s\n' '{"type":"result","subtype":"success","result":"line one\nline two"}' > "$ml"
expect_text "a multi-line answer keeps its lines" "$ml" claude-code "line one
line two"

# --- plain text: the fake CLI's stream is not JSON ---------------------------
plain="$work/plain.txt"
printf 'SKILL yagni\nan answer in plain text\n' > "$plain"
expect_text "plain text falls back to the raw stream" "$plain" fake "SKILL yagni
an answer in plain text"
expect_text "plain text falls back with no harness named" "$plain" "" "SKILL yagni
an answer in plain text"

# --- nothing to read ---------------------------------------------------------
: > "$work/empty"
expect_none "an empty stream yields nothing" "$work/empty" claude-code
expect_none "a missing stream yields nothing" "$work/does-not-exist" claude-code

exit "$fails"
