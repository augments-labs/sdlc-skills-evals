#!/usr/bin/env bash
# The assistant's answer text in a run's stream. Sourced, never executed.
#
# lab_extract_stream_text <stream> [harness] prints the LAST answer the
# stream carries and returns 0, or prints nothing and returns 1:
#   - a terminal summary where the envelope has one (claude/cursor result,
#     antigravity result, hermes result, muse run.terminal.completed);
#   - else the last whole assistant message (codex agent_message, kimi
#     assistant role, opencode text part, pi message_end, claude/cursor
#     assistant text, hermes text record);
#   - else the deltas joined (devin message chunks, grok text deltas,
#     antigravity/muse/pi deltas when nothing whole was emitted).
# Tool calls, tool input JSON, tool output, reasoning and thought chunks are
# never answer text. Naming the harness keeps records of another envelope
# out (hermes and opencode share .type == "text"); with no harness, or one
# this file does not know (the fake CLI), every envelope's shape is read.
# A stream with no JSON object at all (the fake CLI's plain text) is the
# answer as it stands.

_LAB_STREAM_TEXT_JQ='
def txt:
  if type == "string" then .
  elif type == "array" then
    [.[] | select(type == "object" and .type == "text") | .text | strings] | join("")
  else "" end;
def cls:
  if .event == "result" and (.result | type) == "object"
     and (.result.response | type) == "string" then
    {h: "antigravity", k: "final", t: .result.response}
  elif .event == "step_update" and (.step_update | type) == "object"
     and .step_update.step_type == "agent_response"
     and (.step_update.text_delta | type) == "string" then
    {h: "antigravity", k: "delta", t: .step_update.text_delta}
  elif .type == "assistant" and (.message | type) == "object"
     and .message.role == "assistant" then
    {h: "claude", k: "message", t: (.message.content | txt)}
  elif .type == "result" and (.result | type) == "string" then
    {h: "claude", k: "final", t: .result}
  elif .type == "item.completed" and (.item | type) == "object"
     and .item.type == "agent_message" and (.item.text | type) == "string" then
    {h: "codex", k: "message", t: .item.text}
  elif .method == "session/update"
     and .params.update.sessionUpdate == "agent_message_chunk" then
    {h: "devin", k: "delta", t: (.params.update.content.text // "")}
  elif .type == "content_block_delta" and .delta.type == "text_delta" then
    {h: "grok", k: "delta", t: (.delta.text // "")}
  elif .type == "result" and (.text | type) == "string" and (has("part") | not) then
    {h: "hermes", k: "final", t: .text}
  elif .type == "text" and (.text | type) == "string" and (has("part") | not) then
    {h: "hermes", k: "message", t: .text}
  elif .role == "assistant" and has("content") then
    {h: "kimi", k: "message", t: (.content | txt)}
  elif .payload_type == "run.terminal.completed" and (.payload.text | type) == "string" then
    {h: "muse", k: "final", t: .payload.text}
  elif .payload_type == "run.output.delta" and (.payload.text | type) == "string" then
    {h: "muse", k: "delta", t: .payload.text}
  elif .type == "text" and (.part | type) == "object" and .part.type == "text"
     and (.part.text | type) == "string" then
    {h: "opencode", k: "message", t: .part.text}
  elif .type == "message_end" and (.message | type) == "object"
     and .message.role == "assistant" then
    {h: "pi", k: "message", t: (.message.content | txt)}
  elif .type == "message_update" and .assistantMessageEvent.type == "text_delta" then
    {h: "pi", k: "delta", t: (.assistantMessageEvent.delta // "")}
  else empty end;
[ split("\n")[] | fromjson? | objects | (cls)? | select(.t != "")
  | select($fam == "" or .h == $fam) ] as $r
| ([$r[] | select(.k == "final")] | last | .t?)
  // ([$r[] | select(.k == "message")] | last | .t?)
  // ([$r[] | select(.k == "delta") | .t] | if length > 0 then join("") else null end)
  // empty
'

lab_extract_stream_text() { # $1 stream [$2 harness] — prints the answer text
  local stream="${1:-}" harness="${2:-}" family objects text
  [ -s "$stream" ] || return 1
  case "$harness" in
    claude-code|cursor) family=claude ;;
    kimi-code) family=kimi ;;
    antigravity|codex|devin|grok|hermes|muse|opencode|pi) family="$harness" ;;
    *) family="" ;;
  esac
  objects="$(jq -R -s '[split("\n")[] | fromjson? | objects] | length' "$stream" 2>/dev/null)" \
    || return 1
  if [ "$objects" = 0 ]; then
    cat "$stream"
    return 0
  fi
  text="$(jq -R -s -r --arg fam "$family" "$_LAB_STREAM_TEXT_JQ" "$stream" 2>/dev/null)" \
    || return 1
  [ -n "$text" ] || return 1
  printf '%s\n' "$text"
}
