#!/usr/bin/env bash
# Offline test: the opencode adapter parses the observed stream shapes and
# installs the plugin the way the CLI on the machine actually reads it.
#
# The stream fixture mirrors a real `opencode run --format json` envelope
# (one JSON object per line, sessionID beside every event) with part shapes
# observed in the session store (skill input.name, edit/write filePath,
# step-finish tokens). It lives with the other labelled fixtures, under
# lib/tests/fixtures/harnesses/opencode/. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lab="$here/../.."
fix="$here/fixtures/harnesses/opencode"
# shellcheck source=../../harnesses/opencode.sh
source "$lab/harnesses/opencode.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
stream="$work/stream.jsonl"
jq -c '.[]' "$fix/activation.json" > "$stream"

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

# a long session emits one step-finish per step: usage takes the last
# cumulative total, never a concatenation of every step
multi="$work/multi.jsonl"
cp "$stream" "$multi"
cat >> "$multi" <<'EOF'
{"type":"step_finish","timestamp":6,"sessionID":"ses_test","part":{"id":"p6","messageID":"m1","sessionID":"ses_test","type":"step-finish","reason":"stop","tokens":{"total":250,"input":200,"output":50,"reasoning":0,"cache":{"write":0,"read":25}},"cost":0}}
EOF
[ "$(adapter_usage "$multi")" = "250" ] \
  && ok "usage takes the last step total" || bad "usage takes the last step total (got $(adapter_usage "$multi"))"

# empty and error-shaped streams stay silent, never phantom
empty="$work/empty.jsonl"
: > "$empty"
[ -z "$(adapter_chain "$empty")" ] && ok "empty stream has no chain" || bad "empty stream has no chain"
adapter_ran "$empty" && bad "empty stream did not run" || ok "empty stream did not run"
[ -z "$(adapter_usage "$empty" 2>/dev/null)" ] && ok "empty stream has no usage" || bad "empty stream has no usage"
printf '{"type":"error","timestamp":6,"error":{"message":"auth failed"}}\n' > "$work/err.jsonl"
adapter_ran "$work/err.jsonl" && bad "error stream did not run" || ok "error stream did not run"

# session continuation reads the stream's own session id
[ "$(jq -r '.. | objects | .sessionID? // empty' "$stream" | head -1)" = "ses_test" ] \
  && ok "session id readable from stream" || bad "session id readable from stream"

# --- the install --------------------------------------------------------------
# Two generations install the same plugin differently, so the major version
# decides (the pinned upstream's tests/harnesses/opencode.sh, v11.0.0): 1.x
# takes a plugin FILE under `plugin`; 2.x takes a plugin DIRECTORY under
# `plugins` and resolves `<dir>/index.js` inside it.
#
# The version comes from the CLI's own `--version`, so the fake CLI below
# is what answers it: the real opencode is not on this test's PATH.
fakebin="$work/bin"; mkdir -p "$fakebin"
cat > "$fakebin/opencode" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'opencode v%s\n' "${FAKE_OPENCODE_VERSION:-1.9.0}";;
esac
exit 0
EOF
chmod +x "$fakebin/opencode"
PATH="$fakebin:$PATH"; export PATH

plug="$work/plugin-src"
mkdir -p "$plug/.opencode/plugins"
printf 'export default {}\n' > "$plug/.opencode/plugins/sdlc-skills.js"
printf 'export default {}\n' > "$plug/index.js"

FAKE_OPENCODE_VERSION=1.9.0 maxturns=6 adapter_install "$plug"
# Set by adapter_install (sourced above).
# shellcheck disable=SC2154
cfg="$harness_home/xdg/opencode/opencode.json"
jq -e --arg p "$plug/.opencode/plugins/sdlc-skills.js" \
  '.plugin[0] == $p and .agent.build.steps == 6' "$cfg" >/dev/null \
  && ok "1.x install names the plugin file and the step bound" || bad "1.x install names the plugin file and the step bound"
jq -e 'has("plugins") | not' "$cfg" >/dev/null \
  && ok "1.x install writes no plugins key" || bad "1.x install writes no plugins key"
rm -rf "$harness_home"

FAKE_OPENCODE_VERSION=2.0.32 maxturns=6 adapter_install "$plug"
cfg="$harness_home/xdg/opencode/opencode.json"
jq -e --arg p "$plug" \
  '.plugins[0] == $p and .agent.build.steps == 6' "$cfg" >/dev/null \
  && ok "2.x install names the plugin directory and the step bound" || bad "2.x install names the plugin directory and the step bound"
jq -e 'has("plugin") | not' "$cfg" >/dev/null \
  && ok "2.x install writes no plugin key" || bad "2.x install writes no plugin key"
rm -rf "$harness_home"

# a version the adapter does not know is refused, not guessed at
if FAKE_OPENCODE_VERSION=9.9.9 adapter_install "$plug" >/dev/null 2>&1; then
  bad "an unrecognised opencode version is refused"
else
  ok "an unrecognised opencode version is refused"
fi

FAKE_OPENCODE_VERSION=1.9.0 adapter_install "$plug" >/dev/null 2>&1
saved_turns="${maxturns:-}"
unset maxturns
adapter_install "$plug" 2>/dev/null
cfg="$harness_home/xdg/opencode/opencode.json"
jq -e 'has("agent") | not' "$cfg" >/dev/null \
  && ok "install omits steps without maxturns" || bad "install omits steps without maxturns"
maxturns="$saved_turns"
adapter_install "" 2>/dev/null
cfg="$harness_home/xdg/opencode/opencode.json"
jq -e '(has("plugin") | not) and (has("plugins") | not)' "$cfg" >/dev/null \
  && ok "none arm installs no plugin" || bad "none arm installs no plugin"
rm -rf "$harness_home"

exit "$fails"
