#!/usr/bin/env bash
# Offline test: the opencode adapter parses the observed stream shapes.
# The fixture mirrors a real `opencode run --format json` envelope (one
# JSON object per line, sessionID beside every event) with part shapes
# observed in the session store (skill input.name, edit/write filePath,
# step-finish tokens). No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lab="$here/../.."
# shellcheck source=../../harnesses/opencode.sh
source "$lab/harnesses/opencode.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

fix="$(mktemp -d)"
trap 'rm -rf "$fix"' EXIT
stream="$fix/stream.jsonl"
cat > "$stream" <<'EOF'
{"type":"step_start","timestamp":1,"sessionID":"ses_test","part":{"id":"p1","messageID":"m1","sessionID":"ses_test","type":"step-start"}}
{"type":"text","timestamp":2,"sessionID":"ses_test","part":{"id":"p2","messageID":"m1","sessionID":"ses_test","type":"text","text":"looking at the plan"}}
{"type":"tool","timestamp":3,"sessionID":"ses_test","part":{"id":"p3","messageID":"m1","sessionID":"ses_test","type":"tool","tool":"skill","callID":"c1","state":{"status":"completed","input":{"name":"using-git-worktrees"},"metadata":{"name":"using-git-worktrees"},"title":"load skill"}}}
{"type":"tool","timestamp":4,"sessionID":"ses_test","part":{"id":"p4","messageID":"m1","sessionID":"ses_test","type":"tool","tool":"edit","callID":"c2","state":{"status":"completed","input":{"filePath":"src/x.ts","oldString":"a","newString":"b"},"title":"edit file"}}}
{"type":"step_finish","timestamp":5,"sessionID":"ses_test","part":{"id":"p5","messageID":"m1","sessionID":"ses_test","type":"step-finish","reason":"stop","tokens":{"total":100,"input":80,"output":20,"reasoning":0,"cache":{"write":0,"read":10}},"cost":0}}
EOF

[ "$(adapter_chain "$stream")" = "using-git-worktrees" ] \
  && ok "chain reports the invoked skill" || bad "chain reports the invoked skill (got $(adapter_chain "$stream"))"
adapter_behavioral_events "$stream" | grep -qx "SKILL using-git-worktrees" \
  && ok "events report SKILL" || bad "events report SKILL"
adapter_behavioral_events "$stream" | grep -qx "EDIT src/x.ts" \
  && ok "events report EDIT with path" || bad "events report EDIT with path"
adapter_ran "$stream" \
  && ok "stream with model output ran" || bad "stream with model output ran"
[ "$(adapter_usage "$stream")" = "100" ] \
  && ok "usage reports the step total" || bad "usage reports the step total (got $(adapter_usage "$stream"))"

# empty and error-shaped streams stay silent, never phantom
empty="$fix/empty.jsonl"
: > "$empty"
[ -z "$(adapter_chain "$empty")" ] && ok "empty stream has no chain" || bad "empty stream has no chain"
adapter_ran "$empty" && bad "empty stream did not run" || ok "empty stream did not run"
[ -z "$(adapter_usage "$empty" 2>/dev/null)" ] && ok "empty stream has no usage" || bad "empty stream has no usage"
printf '{"type":"error","timestamp":6,"error":{"message":"auth failed"}}\n' > "$fix/err.jsonl"
adapter_ran "$fix/err.jsonl" && bad "error stream did not run" || ok "error stream did not run"

# session continuation reads the stream's own session id
[ "$(jq -r '.. | objects | .sessionID? // empty' "$stream" | head -1)" = "ses_test" ] \
  && ok "session id readable from stream" || bad "session id readable from stream"

# install writes an isolated config naming the pinned plugin (offline)
plug="$fix/plugin-src"
mkdir -p "$plug"
maxturns=6 adapter_install "$plug"
cfg="$harness_home/xdg/opencode/opencode.json"
jq -e --arg p "$plug/.opencode/plugins/sdlc-skills.js" \
  '.plugin[0] == $p and .agent.build.steps == 6' "$cfg" >/dev/null \
  && ok "install pins plugin and step bound" || bad "install pins plugin and step bound"
saved_turns="${maxturns:-}"
unset maxturns
adapter_install "$plug" 2>/dev/null
jq -e 'has("agent") | not' "$harness_home/xdg/opencode/opencode.json" >/dev/null \
  && ok "install omits steps without maxturns" || bad "install omits steps without maxturns"
maxturns="$saved_turns"
adapter_install "" 2>/dev/null
jq -e 'has("plugin") | not' "$harness_home/xdg/opencode/opencode.json" >/dev/null \
  && ok "none arm installs no plugin" || bad "none arm installs no plugin"
rm -rf "$harness_home"

exit "$fails"
