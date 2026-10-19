#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# Contract: headers are read by runners via grep; globals (timeout_s, errlog,
# plugin_dir, harness_home) are set by the runner sourcing this file.
# Devin CLI adapter. Sourced by the runners — never executed directly.
#
# This file holds only what is true of the `devin` CLI: how the plugin is
# loaded, how it is invoked, how an activation is detected, and what a run
# costs. Anything harness-agnostic belongs in the runner, not here.
#
# EVIDENCE CLASS: documentation-grounded, runtime unverified.
#   - The install facts come from the pinned upstream's tests/harnesses/devin.sh
#     (upstream 638040d, v11.0.0): devin installs `plugins/sdlc-skills/` — the
#     Codex plugin directory — with `devin plugins install --local`, which
#     LINKS the folder in place rather than copying it, and plugin management
#     refuses to run signed out, so the credentials file is copied into the
#     throwaway home. The upstream lists a plugin's skills as
#     `/sdlc-skills:<name>`, which is the namespace this adapter matches.
#   - The observation interface is the ACP (Agent Client Protocol) server the
#     CLI ships: `devin acp` speaks JSON-RPC 2.0 over stdio, and the v1
#     schema is compiled into the devin 3000.11.3 binary
#     (`agent_client_protocol_schema::v1`: InitializeRequest, SessionUpdate,
#     ToolCall, UsageUpdate). The adapter drives it as an ACP client:
#     `initialize`, `session/new`, `session/prompt`, and it answers the
#     agent's `session/request_permission` requests.
#   - The parser is exercised against LABELLED SYNTHETIC fixtures under
#     lib/tests/fixtures/harnesses/devin/. No devin ACP session has been
#     observed on this machine, so every capability below is documentation
#     and `runnable` stays `no` until a real run replaces the label.

adapter_name='devin'

runnable=no
runnable_reason="devin 3000.11.3 is on PATH and its ACP schema is compiled into the binary, but no devin ACP session has been recorded on this machine"
# The permission-relevant flag this file passes is devin's own permission
# mode; which mode depends on the arm, so the header names the flag.
permission_flags="--permission-mode"
capabilities="subagent-loads-skills=no(documentation) nesting-depth=unknown(documentation) tier-settable=no(documentation) session-start-event=yes(documentation) post-compaction-event=unknown(documentation)"

source_devin_data="${XDG_DATA_HOME:-${HOME:-}/.local/share}/devin"

_libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$_libdir/common.sh"

adapter_check() {
  command -v devin >/dev/null 2>&1 || { echo "no \`devin\` CLI on PATH" >&2; return 3; }
}

# Isolated HOME with `devin plugins install --local`, which links the folder
# in place and, unlike a remote install, never writes the account's cloud
# plugin manifest. Plugin management refuses to run signed out even for a
# local folder, so the credentials file is copied in. HOME is isolated
# rather than devin's own directories alone because devin also reads
# `~/.claude/` hooks and skills, which would answer for the tree under test.
#
# The environment is kept, not cleared with `env -i`: measured on 3000.11.3,
# the install checks the organisation's plugin policy over the network and a
# cleared environment times that request out.
#
# The NONE arm is an isolated home with credentials and no plugin.
adapter_install() { # $1 plugin source ("" = NONE arm, load nothing)
  harness_home="$(mktemp -d)"
  plugin_dir="$1/plugins/sdlc-skills"
  mkdir -p "$harness_home/.local/share/devin"
  [ -f "$source_devin_data/credentials.toml" ] &&
    cp "$source_devin_data/credentials.toml" "$harness_home/.local/share/devin/"
  [ -n "${1:-}" ] || return 0
  ( cd "$harness_home" && env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
      HOME="$harness_home" \
      devin plugins install --local "$plugin_dir" -y </dev/null ) >>"$errlog" 2>&1 || {
    echo "devin plugins install failed (see $errlog)" >&2; return 1; }
  return 0
}

# The plugin comes from the installed plugin set, not from a flag.
adapter_activation_flags() { :; }

# No suffix: devin runs the plugin's SessionStart hook, which injects the
# router, so the opening goes in bare.
adapter_prompt_suffix() { :; }

# DETECTION: an ACP `session/update` whose update is a `tool_call` and whose
# title or raw input names a skill — by the `sdlc-skills:` namespace the
# plugin format carries, or by a SKILL.md path, whose directory above it is
# the skill's name. Only a tool_call update counts: an agent message that
# merely mentions a skill is not an activation.
adapter_chain() { # $1 stream file (ACP JSON-RPC stream)
  jq -r 'select(.method == "session/update")
         | select(.params.update.sessionUpdate == "tool_call")
         | (.params.update | tostring) as $all
         | ([$all | match("(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md"; "g")]
            | map(.captures[0].string) | .[0]) as $dir
         | ([$all | match("sdlc-skills:(?<skill>[A-Za-z0-9_-]+)"; "g")]
            | map(.captures[0].string) | .[0]) as $ns
         | if $dir != null then $dir
           elif $ns != null then $ns
           else empty end' "$1" 2>/dev/null
}

# Normalize structured actions for cross-harness behavioural assertions.
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.method == "session/update")
         | select(.params.update.sessionUpdate == "tool_call")
         | (.params.update | tostring) as $all
         | ([$all | match("(?<skill>[A-Za-z0-9_-]+)/SKILL[.]md"; "g")]
            | map(.captures[0].string) | .[0]) as $dir
         | ([$all | match("sdlc-skills:(?<skill>[A-Za-z0-9_-]+)"; "g")]
            | map(.captures[0].string) | .[0]) as $ns
         | ([$all | match("(?<path>[A-Za-z0-9_./-]+)"; "g")]
            | map(.captures[0].string)
            | map(select(test("SKILL[.]md$") | not))
            | map(select(test("/") )) | .[0]) as $file
         | if $dir != null then "SKILL " + $dir
           elif $ns != null then "SKILL " + $ns
           elif $file != null then "EDIT " + $file
           else empty end' "$1" 2>/dev/null
}

# DID IT RUN? An agent message chunk means the model spoke; a dead provider
# emits none.
adapter_ran() { # $1 stream file
  jq -e -s 'any(.[]; .method == "session/update"
                   and .params.update.sessionUpdate == "agent_message_chunk")' \
    >/dev/null 2>&1 <"$1"
}

# COST: an ACP `usage_update` carries the run's token counts. The explicit
# total wins; otherwise input and output are added. Silent when no usage
# update arrives, so a timed-out or refused run reports no number rather
# than a misleading zero.
adapter_usage() { # $1 stream file
  jq -s '([.[] | select(.method == "session/update")
            | select(.params.update.sessionUpdate == "usage_update")
            | .params.update
            | (.total_tokens // ((.input_tokens // 0) + (.output_tokens // 0)))]
          | map(select(. != null)) | last) // empty' "$1" 2>/dev/null
}

# --- the ACP client ------------------------------------------------------------
#
# `devin acp` is a JSON-RPC 2.0 server over stdio. The adapter is its
# client: it initializes, opens a session on the run's working directory,
# sends the prompt, and answers the agent's permission requests. The session
# id comes from `session/new`'s own answer, so it is never invented.

_devin_answered=""   # ids of the permission requests already answered

# Answer one pending permission request, if any is unanswered.
_devin_acp_answer() { # $1 stream  $2 fd  $3 read-only?|all
  local stream="$1" fd="$2" mode="$3" req_id="" cand opt kind
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    case " $_devin_answered " in *" $cand "*) continue ;; esac
    req_id="$cand"; break
  done < <(jq -r 'select(.method? == "session/request_permission") | .id // empty' \
             "$stream" 2>/dev/null)
  [ -n "$req_id" ] || return 1
  _devin_answered="$_devin_answered $req_id"
  kind="$(jq -r --argjson id "$req_id" 'select(.id? == $id)
              | .params.toolCall.kind // empty' "$stream" 2>/dev/null)"
  if [ "$mode" = read ] && [ "$kind" != read ]; then
    opt="$(jq -r --argjson id "$req_id" 'select(.id? == $id)
            | .params.options[]? | select(.kind == "reject_once") | .optionId // empty' \
            "$stream" 2>/dev/null | head -1)"
    [ -n "$opt" ] || opt="$(jq -r --argjson id "$req_id" 'select(.id? == $id)
            | .params.options[]? | .optionId // empty' "$stream" 2>/dev/null | head -1)"
    [ -n "$opt" ] || return 0
    printf '{"jsonrpc":"2.0","id":%s,"result":{"outcome":{"outcome":"selected","optionId":"%s"}}}\n' \
      "$req_id" "$opt" >&"$fd"
    return 0
  fi
  opt="$(jq -r --argjson id "$req_id" 'select(.id? == $id)
          | .params.options[]? | select(.kind == "allow_once") | .optionId // empty' \
          "$stream" 2>/dev/null | head -1)"
  [ -n "$opt" ] || opt="$(jq -r --argjson id "$req_id" 'select(.id? == $id)
          | .params.options[]? | .optionId // empty' "$stream" 2>/dev/null | head -1)"
  [ -n "$opt" ] || return 0
  printf '{"jsonrpc":"2.0","id":%s,"result":{"outcome":{"outcome":"selected","optionId":"%s"}}}\n' \
    "$req_id" "$opt" >&"$fd"
  return 0
}

# Wait for the answer to request $2, answering permission requests meanwhile.
_devin_acp_wait() { # $1 stream  $2 id  $3 fd  $4 read-only?|all  $5 pid
  local stream="$1" want="$2" fd="$3" mode="$4" pid="$5" waited=0 limit
  limit=$(( timeout_s * 5 ))
  while [ "$waited" -lt "$limit" ]; do
    _devin_acp_answer "$stream" "$fd" "$mode" >/dev/null 2>&1 || true
    if jq -e --argjson id "$want" 'select(.id? == $id)' "$stream" >/dev/null 2>&1; then
      return 0
    fi
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.2; waited=$((waited + 1))
  done
  return 1
}

_devin_acp_run() { # $1 workdir  $2 prompt  $3 stream  $4 read-only?|all  $5 cli permission mode
  local wd="$1" prompt="$2" stream="$3" mode="$4"
  local fifo pid waited=0 limit sid
  fifo="$(mktemp -u "${TMPDIR:-/tmp}/devin-acp.XXXXXX")" || return 1
  mkfifo "$fifo" || return 1
  # The parent holds the fifo open READ-WRITE, so neither the open below nor
  # the child's read-only open can deadlock on the other side. The child
  # sees EOF when this handle is closed, which is the end of the session.
  exec 3<>"$fifo" || { rm -f "$fifo"; return 1; }
  # The child must not keep the parent's write handle: it would never see
  # the EOF that ends the session.
  ( cd "$wd" && exec 3<&- && exec devin --permission-mode "$5" acp ) \
    < "$fifo" > "$stream" 2>>"$errlog" &
  pid=$!

  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false}}}}' >&3
  _devin_acp_wait "$stream" 1 3 "$mode" "$pid" || { exec 3>&-; kill "$pid" 2>/dev/null; rm -f "$fifo"; return 1; }

  printf '%s\n' "$(jq -nc --arg cwd "$wd" \
    '{jsonrpc:"2.0",id:2,method:"session/new",params:{cwd:$cwd,mcpServers:[]}}')" >&3
  _devin_acp_wait "$stream" 2 3 "$mode" "$pid" || { exec 3>&-; kill "$pid" 2>/dev/null; rm -f "$fifo"; return 1; }
  sid="$(jq -r 'select(.id? == 2) | .result.sessionId // empty' "$stream" 2>/dev/null | head -1)"
  [ -n "$sid" ] || { exec 3>&-; kill "$pid" 2>/dev/null; rm -f "$fifo"; return 1; }

  printf '%s\n' "$(jq -nc --arg sid "$sid" --arg p "$prompt" \
    '{jsonrpc:"2.0",id:3,method:"session/prompt",params:{sessionId:$sid,prompt:[{type:"text",text:$p}]}}')" >&3
  limit=$(( timeout_s * 5 ))
  while [ "$waited" -lt "$limit" ]; do
    _devin_acp_answer "$stream" 3 "$mode" >/dev/null 2>&1 || true
    if jq -e 'select(.id? == 3)' "$stream" >/dev/null 2>&1; then break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2; waited=$((waited + 1))
  done
  exec 3>&-
  wait "$pid" 2>/dev/null
  rm -f "$fifo"
  return 0
}

# Activation probe: one query, bounded by the wall clock. The arm is
# read-only twice over: `--permission-mode auto` auto-approves read-only
# tools only, and the ACP permission answer allows a read-kind tool call
# and refuses the rest. The workdir is a disposable fixture and HOME is the
# throwaway run home.
adapter_run_activation() { # $1 workdir  $2 prompt  $3 stream  $4... extra flags
  local wd="$1" prompt="$2" stream="$3"; shift 3
  export -f _devin_acp_run _devin_acp_wait _devin_acp_answer
  ( cd "$wd" && exec timeout "$timeout_s" env HOME="$harness_home" \
      XDG_DATA_HOME="$harness_home/.local/share" TMPDIR="${TMPDIR:-/tmp}" \
      bash -c '_devin_acp_run "$1" "$2" "$3" read auto' _ "$wd" "$prompt" "$stream" ) \
    < /dev/null > /dev/null 2>>"$errlog"
}

# WRITE access — a behavioural arm must be able to produce artifacts. Safe:
# the run happens in a disposable fixture copy under TMPDIR, never in a real
# checkout, under the throwaway run home.
adapter_run_behavioral() { # $1 workdir  $2 opening file  $3 stream
  export -f _devin_acp_run _devin_acp_wait _devin_acp_answer
  ( cd "$1" && exec timeout "$timeout_s" env HOME="$harness_home" \
      XDG_DATA_HOME="$harness_home/.local/share" TMPDIR="${TMPDIR:-/tmp}" \
      bash -c '_devin_acp_run "$1" "$2" "$3" all accept-edits' _ "$1" "$(cat "$2")" "$3" ) \
    < /dev/null > /dev/null 2>>"$errlog"
}

# Continue the same behavioural session. The session id comes from the prior
# stream's own `session/new` answer; an absent id is an adapter error, not a
# fresh-session substitute.
adapter_continue_behavioral() { # $1 workdir  $2 prompt  $3 new stream  $4 prior stream
  local wd="$1" prompt="$2" out="$3" prior="$4" session_id
  session_id="$(jq -r 'select(.id? == 2) | .result.sessionId // empty' \
    "$prior" 2>/dev/null | head -1)"
  [ -n "$session_id" ] || { echo "Devin stream contains no resumable session id" >&2; return 2; }
  export -f _devin_acp_run _devin_acp_wait _devin_acp_answer
  ( cd "$wd" && exec timeout "$timeout_s" env HOME="$harness_home" \
      XDG_DATA_HOME="$harness_home/.local/share" TMPDIR="${TMPDIR:-/tmp}" \
      bash -c '_devin_acp_run "$1" "$2" "$3" all accept-edits' _ "$wd" "$prompt" "$out" ) \
    < /dev/null > /dev/null 2>>"$errlog"
}

# NO adapter_model: devin takes `--model` and its own fuzzy names, but no
# official small/medium/large mapping exists. A scenario that asks for a
# tier is refused by the runner rather than run on the default model and
# called that tier.
