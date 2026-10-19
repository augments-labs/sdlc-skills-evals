#!/usr/bin/env bash
# Offline test: every harness adapter honours the lab contract, against a
# FAKE CLI. No live run, no credential, no model, no network.
#
# The fake CLI records every invocation, so an adapter that reaches a real
# CLI fails instead of launching it: the real CLIs are not on this test's
# PATH. The streams the parsers read are LABELLED SYNTHETIC fixtures under
# lib/tests/fixtures/harnesses/<harness>/ — never a real observation.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lab="$(cd "$here/../.." && pwd)"
hh="$lab/harnesses"
fix="$here/fixtures/harnesses"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

INVENTORY="${INVENTORY_PATH:-$lab/config/upstream-inventory.json}"
command -v jq >/dev/null 2>&1 || { echo "needs \`jq\`" >&2; exit 2; }
[ -f "$INVENTORY" ] || { echo "no upstream inventory at $INVENTORY" >&2; exit 2; }

mapfile -t adapters < <(jq -r '.harnesses[]' "$INVENTORY")

# --- the adapter set equals the inventory, exactly ---------------------------
found="$(cd "$hh" && ls *.sh 2>/dev/null | sed 's/\.sh$//' | sort)"
want="$(printf '%s\n' "${adapters[@]}" | sort)"
if [ "$found" = "$want" ]; then
  ok "adapter set equals the $(printf '%s\n' "${adapters[@]}" | wc -l | tr -d ' ')-member inventory"
else
  bad "adapter set equals the inventory (have: $(printf '%s' "$found" | tr '\n' ' '))"
fi

# --- the expectations table --------------------------------------------------
# skill:   the skill the activation fixture must yield
# install: a fragment the install invocation log must contain
# launch:  a fragment the launch invocation log must contain
# usage:   the number the activation fixture must yield, or "-"
# resume:  yes when the adapter implements adapter_continue_behavioral
# tier:    yes when the adapter implements adapter_model
expect() { # $1 harness  $2 key
  case "$1/$2" in
    antigravity/skill) echo "using-sdlc-skills";;
    antigravity/install) echo "agy plugin install";;
    antigravity/launch) echo "agy";;
    antigravity/usage) echo "125";;
    antigravity/resume) echo "yes";;
    antigravity/tier) echo "no";;
    claude-code/skill) echo "using-sdlc-skills";;
    claude-code/install) echo "";;
    claude-code/launch) echo "claude";;
    claude-code/usage) echo "165";;
    claude-code/resume) echo "yes";;
    claude-code/tier) echo "yes";;
    codex/skill) echo "sdlc-skills:using-sdlc-skills";;
    codex/install) echo "codex plugin marketplace add";;
    codex/launch) echo "codex exec";;
    codex/usage) echo "60";;
    codex/resume) echo "yes";;
    codex/tier) echo "no";;
    cursor/skill) echo "using-sdlc-skills";;
    cursor/install) echo "";;
    cursor/launch) echo "cursor-agent";;
    cursor/usage) echo "-";;
    cursor/resume) echo "yes";;
    cursor/tier) echo "no";;
    devin/skill) echo "using-sdlc-skills";;
    devin/install) echo "devin plugins install";;
    devin/launch) echo "devin";;
    devin/usage) echo "81";;
    devin/resume) echo "yes";;
    devin/tier) echo "no";;
    grok/skill) echo "using-sdlc-skills";;
    grok/install) echo "grok plugin install";;
    grok/launch) echo "grok";;
    grok/usage) echo "120";;
    grok/resume) echo "no";;
    grok/tier) echo "no";;
    hermes/skill) echo "sdlc-skills:using-sdlc-skills";;
    hermes/install) echo "hermes plugins install";;
    hermes/launch) echo "hermes";;
    hermes/usage) echo "102";;
    hermes/resume) echo "yes";;
    hermes/tier) echo "no";;
    kimi-code/skill) echo "sdlc-skills:using-sdlc-skills";;
    kimi-code/install) echo "";;
    kimi-code/launch) echo "kimi";;
    kimi-code/usage) echo "-";;
    kimi-code/resume) echo "yes";;
    kimi-code/tier) echo "no";;
    muse/skill) echo "using-sdlc-skills";;
    muse/install) echo "";;
    muse/launch) echo "muse exec";;
    muse/usage) echo "90";;
    muse/resume) echo "yes";;
    muse/tier) echo "no";;
    opencode/skill) echo "using-git-worktrees";;
    opencode/install) echo "";;
    opencode/launch) echo "opencode run";;
    opencode/usage) echo "100";;
    opencode/resume) echo "yes";;
    opencode/tier) echo "no";;
    pi/skill) echo "using-sdlc-skills";;
    pi/install) echo "pi install";;
    pi/launch) echo "pi";;
    pi/usage) echo "120";;
    pi/resume) echo "yes";;
    pi/tier) echo "no";;
    *) echo "";;
  esac
}

# --- one adapter at a time ---------------------------------------------------
# Every adapter defines the same function names, so each one is sourced in
# its own shell.
check_adapter() { # $1 harness
  local h="$1" f=0
  ok() { printf '  ok    %s\n' "$1"; }
  bad() { printf '  FAIL  %s\n' "$1"; f=1; }
  local work bin plug wd stream errlog log
  work="$(mktemp -d)" || return 1
  bin="$work/bin"; mkdir -p "$bin"
  for c in agy claude codex cursor-agent devin grok hermes kimi muse opencode pi; do
    cp "$fix/fake-cli.sh" "$bin/$c"; chmod +x "$bin/$c"
  done
  # The plugin tree under test: a git checkout, like the real one.
  plug="$work/plugin"
  mkdir -p "$plug/skills/common/using-sdlc-skills" "$plug/scripts/sh" \
           "$plug/plugins/sdlc-skills/rules" "$plug/.opencode/plugins" \
           "$plug/.kimi-plugin" "$plug/.claude-plugin"
  printf -- '---\nname: using-sdlc-skills\ndescription: router\n---\n\nbody\n' \
    > "$plug/skills/common/using-sdlc-skills/SKILL.md"
  printf '# SDLC skills\n\nInvoke the `using-sdlc-skills` skill.\n' \
    > "$plug/plugins/sdlc-skills/rules/AGENTS.md"
  printf '{}\n' > "$plug/.kimi-plugin/plugin.json"
  printf '{}\n' > "$plug/.claude-plugin/plugin.json"
  printf 'export default {}\n' > "$plug/.opencode/plugins/sdlc-skills.js"
  printf 'export default {}\n' > "$plug/index.js"
  # A stand-in for the plugin's own muse install script: the real one lives
  # in the plugin repository, not in this lab.
  cat > "$plug/scripts/sh/install-muse-skills.sh" <<'EOS'
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2
command -v muse >/dev/null 2>&1 || exit 3
mapfile -t dirs < <(find skills -mindepth 3 -maxdepth 3 -name SKILL.md -exec dirname {} \; | sort)
[ "${#dirs[@]}" -gt 0 ] || exit 2
for dir in "${dirs[@]}"; do
  out="$(muse skills install "$dir" --scope user --force --json 2>&1)" || exit 1
done
EOS
  git -C "$plug" init -q >/dev/null 2>&1
  git -C "$plug" add -A >/dev/null 2>&1
  git -C "$plug" -c user.name=lab -c user.email=lab@example.invalid \
    commit -qm fixture >/dev/null 2>&1

  wd="$work/workdir"; mkdir -p "$wd"
  stream="$work/stream.jsonl"; errlog="$work/err.log"; log="$work/calls.log"
  export FAKE_HARNESS_LOG="$log"
  export HOME="$work/home"; mkdir -p "$HOME"
  export TMPDIR="$work/tmp"; mkdir -p "$TMPDIR"
  export timeout_s=5
  export maxturns=6
  export errlog
  unset scenario_model_tier 2>/dev/null || true
  # The fake CLI is the ONLY agent CLI on PATH: the real ones are not
  # reachable, so an adapter that reaches one fails instead of launching it.
  export PATH="$bin:/usr/bin:/bin"

  # shellcheck source=/dev/null
  source "$hh/$h.sh" || { bad "$h sources"; return 1; }

  # --- the missing CLI: adapter_check must refuse ----------------------------
  local saved_path="$PATH"
  PATH="/usr/bin:/bin"
  if adapter_check >/dev/null 2>&1; then
    bad "$h adapter_check refuses when the CLI is missing"
  else
    ok "$h adapter_check refuses when the CLI is missing"
  fi
  PATH="$saved_path"
  # --- the install -----------------------------------------------------------
  local install_pattern; install_pattern="$(expect "$h" install)"
  if adapter_install "$plug" >/dev/null 2>"$work/install.err"; then
    ok "$h install succeeds against the fake CLI"
  else
    bad "$h install succeeds against the fake CLI (see $work/install.err)"
  fi
  if [ -n "${harness_home:-}" ] && [ -d "$harness_home" ]; then
    ok "$h install records an isolated home"
  else
    bad "$h install records an isolated home"
  fi
  local calls; calls="$(cat "$log" 2>/dev/null; cat "$harness_home/.fake-harness.log" 2>/dev/null)"
  if [ -z "$install_pattern" ]; then
    ok "$h install needs no CLI invocation"
  elif printf '%s\n' "$calls" | grep -qF -- "$install_pattern"; then
    ok "$h install invokes the CLI ($install_pattern)"
  else
    bad "$h install invokes the CLI ($install_pattern) — log: $(printf '%s' "$calls" | tr '\n' '|')"
  fi

  # --- the none arm ----------------------------------------------------------
  : > "$log"
  local none_calls
  if adapter_install "" >/dev/null 2>"$work/none.err"; then
    ok "$h none arm installs"
  else
    bad "$h none arm installs (see $work/none.err)"
  fi
  none_calls="$(cat "$log" 2>/dev/null; cat "$harness_home/.fake-harness.log" 2>/dev/null)"
  if [ -n "$install_pattern" ] && printf '%s\n' "$none_calls" | grep -qF -- "$install_pattern"; then
    bad "$h none arm installs no plugin"
  else
    ok "$h none arm installs no plugin"
  fi

  # --- the launch ------------------------------------------------------------
  : > "$log"
  printf 'fake stdout\n' > "$work/fake-stdout"
  cp "$work/fake-stdout" "$HOME/.fake-stdout"
  export FAKE_STDOUT="$work/fake-stdout"
  printf 'the opening\n' > "$work/opening"
  if adapter_run_activation "$wd" "the prompt" "$stream" >/dev/null 2>"$work/run.err"; then
    ok "$h activation launch succeeds against the fake CLI"
  else
    bad "$h activation launch succeeds against the fake CLI (see $work/run.err)"
  fi
  local launch_pattern; launch_pattern="$(expect "$h" launch)"
  local launch_calls; launch_calls="$(cat "$log" 2>/dev/null; cat "$harness_home/.fake-harness.log" 2>/dev/null)"
  if printf '%s\n' "$launch_calls" | grep -qF -- "$launch_pattern"; then
    ok "$h activation launch reaches the CLI ($launch_pattern)"
  else
    bad "$h activation launch reaches the CLI ($launch_pattern) — log: $(printf '%s' "$launch_calls" | tr '\n' '|')"
  fi
  if [ -s "$stream" ]; then
    ok "$h activation launch captures the CLI's output"
  else
    bad "$h activation launch captures the CLI's output"
  fi
  if adapter_run_behavioral "$wd" "$work/opening" "$stream" >/dev/null 2>"$work/beh.err"; then
    ok "$h behavioural launch succeeds against the fake CLI"
  else
    bad "$h behavioural launch succeeds against the fake CLI (see $work/beh.err)"
  fi
  unset FAKE_STDOUT

  # --- the parsers -----------------------------------------------------------
  local skill; skill="$(expect "$h" skill)"
  local act="$fix/$h/activation.json" neg="$fix/$h/negative.json" unk="$fix/$h/unknown.json"
  jq -c '.[]' "$act" > "$work/act.jsonl"
  jq -c '.[]' "$neg" > "$work/neg.jsonl"
  jq -c '.[]' "$unk" > "$work/unk.jsonl"
  local got
  got="$(adapter_chain "$work/act.jsonl" 2>/dev/null | head -1)"
  if [ "$got" = "$skill" ]; then
    ok "$h chain reports the invoked skill from the activation fixture"
  else
    bad "$h chain reports the invoked skill from the activation fixture (got '${got:-none}')"
  fi
  # an adapter whose skill record has more than one form carries a second
  # positive fixture, so each form is exercised
  if [ -f "$fix/$h/activation-alt.json" ]; then
    jq -c '.[]' "$fix/$h/activation-alt.json" > "$work/alt.jsonl"
    got="$(adapter_chain "$work/alt.jsonl" 2>/dev/null | head -1)"
    if [ "$got" = "$skill" ]; then
      ok "$h chain reports the invoked skill from the second activation fixture"
    else
      bad "$h chain reports the invoked skill from the second activation fixture (got '${got:-none}')"
    fi
  fi
  got="$(adapter_chain "$work/neg.jsonl" 2>/dev/null)"
  if [ -z "$got" ]; then
    ok "$h chain is empty on a stream with no skill"
  else
    bad "$h chain is empty on a stream with no skill (got '$got')"
  fi
  got="$(adapter_chain "$work/unk.jsonl" 2>/dev/null)"
  if [ -z "$got" ]; then
    ok "$h chain is empty on an unknown stream format"
  else
    bad "$h chain is empty on an unknown stream format (got '$got')"
  fi

  # malformed and empty output
  printf '{"type":"tool", not json at all\n' > "$work/bad.jsonl"
  got="$(adapter_chain "$work/bad.jsonl" 2>/dev/null)"
  if [ -z "$got" ]; then
    ok "$h chain is empty on malformed output"
  else
    bad "$h chain is empty on malformed output (got '$got')"
  fi
  : > "$work/empty.jsonl"
  got="$(adapter_chain "$work/empty.jsonl" 2>/dev/null)"
  if [ -z "$got" ]; then
    ok "$h chain is empty on empty output"
  else
    bad "$h chain is empty on empty output (got '$got')"
  fi

  # the refusal: the model never spoke
  printf '{"type":"error","error":{"message":"usage limit exceeded"}}\n' > "$work/refusal.jsonl"
  if command -v adapter_ran >/dev/null 2>&1; then
    if adapter_ran "$work/refusal.jsonl" >/dev/null 2>&1; then
      bad "$h reports no run for a refused stream"
    else
      ok "$h reports no run for a refused stream"
    fi
    if adapter_ran "$work/act.jsonl" >/dev/null 2>&1; then
      ok "$h reports a run for a stream with model output"
    else
      bad "$h reports a run for a stream with model output"
    fi
    if adapter_ran "$work/empty.jsonl" >/dev/null 2>&1; then
      bad "$h reports no run for an empty stream"
    else
      ok "$h reports no run for an empty stream"
    fi
  else
    ok "$h binds no adapter_ran (the runner treats that as 'it ran')"
  fi

  # usage: missing and present
  local usage; usage="$(expect "$h" usage)"
  if [ "$usage" = "-" ]; then
    if command -v adapter_usage >/dev/null 2>&1; then
      got="$(adapter_usage "$work/act.jsonl" 2>/dev/null)"
      if [ -z "$got" ]; then
        ok "$h reports no usage for a stream that carries none"
      else
        bad "$h reports no usage for a stream that carries none (got '$got')"
      fi
    else
      ok "$h binds no adapter_usage (its stream format documents no usage field)"
    fi
  else
    got="$(adapter_usage "$work/neg.jsonl" 2>/dev/null)"
    if [ -z "$got" ]; then
      ok "$h reports no usage when the stream carries none"
    else
      bad "$h reports no usage when the stream carries none (got '$got')"
    fi
    got="$(adapter_usage "$work/act.jsonl" 2>/dev/null)"
    if [ "$got" = "$usage" ]; then
      ok "$h usage reports the run's own total ($usage)"
    else
      bad "$h usage reports the run's own total (expected $usage, got '${got:-none}')"
    fi
  fi

  # --- the resume path -------------------------------------------------------
  if [ "$(expect "$h" resume)" = "yes" ]; then
    printf '{"type":"nothing","session":"no"}\n' > "$work/nosession.jsonl"
    if adapter_continue_behavioral "$wd" "next" "$work/next.jsonl" "$work/nosession.jsonl" \
        >/dev/null 2>"$work/resume.err"; then
      bad "$h refuses to continue a session it cannot identify"
    else
      ok "$h refuses to continue a session it cannot identify"
    fi
  else
    if command -v adapter_continue_behavioral >/dev/null 2>&1; then
      bad "$h binds no adapter_continue_behavioral (its stream carries no session id)"
    else
      ok "$h binds no adapter_continue_behavioral (its stream carries no session id)"
    fi
  fi

  # --- the tier path ---------------------------------------------------------
  if [ "$(expect "$h" tier)" = "yes" ]; then
    if [ "$(adapter_model small 2>/dev/null)" = "haiku" ] &&
       [ "$(adapter_model medium 2>/dev/null)" = "sonnet" ] &&
       [ "$(adapter_model large 2>/dev/null)" = "opus" ]; then
      ok "$h binds a tier to a model"
    else
      bad "$h binds a tier to a model"
    fi
    if adapter_model nonsense >/dev/null 2>&1; then
      bad "$h refuses an unknown tier"
    else
      ok "$h refuses an unknown tier"
    fi
    # The tier is read by the adapter (a different file), so shellcheck
    # cannot see the use from here.
    # shellcheck disable=SC2034
    scenario_model_tier=medium
    if adapter_model_flags 2>/dev/null | grep -qx -- "--model" &&
       adapter_model_flags 2>/dev/null | grep -qx -- "sonnet"; then
      ok "$h passes the tier's model only when a tier is asked for"
    else
      bad "$h passes the tier's model only when a tier is asked for"
    fi
    unset scenario_model_tier
    if [ -z "$(adapter_model_flags 2>/dev/null)" ]; then
      ok "$h passes no model when no tier is asked for"
    else
      bad "$h passes no model when no tier is asked for"
    fi
  else
    if command -v adapter_model >/dev/null 2>&1; then
      bad "$h binds no tier (the CLI documents no small/medium/large mapping)"
    else
      ok "$h binds no tier (the CLI documents no small/medium/large mapping)"
    fi
  fi

  rm -rf "$work"
  return "$f"
}

for h in "${adapters[@]}"; do
  ( check_adapter "$h" ) || fails=1
done

# --- one harness's stream is never another harness's activation --------------
# An unknown format cannot become an activation: every parser must ignore
# every OTHER harness's activation fixture.
cross() { # $1 parser harness  $2 fixture harness
  local f=0 tmp got
  tmp="$(mktemp)"
  jq -c '.[]' "$fix/$2/activation.json" > "$tmp"
  got="$(cd "$hh" && bash -c '
    set -uo pipefail
    source "$1/$2.sh" >/dev/null 2>&1
    adapter_chain "$3" 2>/dev/null
  ' _ "$hh" "$1" "$tmp" 2>/dev/null)"
  rm -f "$tmp"
  if [ -n "$got" ]; then
    printf '  FAIL  %s does not read %s activation fixture as its own (%s)\n' "$1" "$2" "$got"
    f=1
  else
    printf '  ok    %s does not read %s activation fixture as its own\n' "$1" "$2"
  fi
  return "$f"
}
for a in "${adapters[@]}"; do
  for b in "${adapters[@]}"; do
    [ "$a" = "$b" ] && continue
    cross "$a" "$b" || fails=1
  done
done

exit "$fails"
