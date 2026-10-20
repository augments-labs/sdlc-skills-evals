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

# The operator's own home and session bus, captured BEFORE the test replaces
# HOME: an adapter must hand its CLI no route to either. The Linux secret
# service — where the Antigravity CLI keeps its account token — is reachable
# only through the session bus, so a bus address that points at the
# operator's is a route to the operator's credential.
OPERATOR_HOME="${HOME:-}"
OPERATOR_DBUS="${DBUS_SESSION_BUS_ADDRESS:-}"

# The operator's own variables, by NAME. The test exports each of them as a
# SENTINEL — a path inside this test's own work directory — before it
# sources an adapter, so the assertion does not depend on the developer's
# shell and so an adapter that inherits the operator's environment is caught
# rather than assumed absent.
#
# The bus is in the list because of how a session bus is found: with no
# DBUS_SESSION_BUS_ADDRESS and no XDG_RUNTIME_DIR, a D-Bus client falls back
# to the passwd entry's runtime directory — the operator's own. So a launch
# that clears the environment without giving the CLI a runtime directory of
# its own still reaches the operator's bus.
OPERATOR_VARS="XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR \
DBUS_SESSION_BUS_ADDRESS CODEX_HOME CLAUDE_CONFIG_DIR KIMI_CODE_HOME \
GROK_HOME HERMES_HOME PI_HOME CURSOR_HOME AGY_CLI_DISABLE_AUTO_UPDATE \
MUSE_NO_AUTO_UPDATE DISABLE_AUTOUPDATER"

# Every agent CLI name the adapters drive, and the name the fake answers to.
CLI_NAMES="agy claude codex cursor-agent devin grok hermes kimi muse opencode pi"

INVENTORY="${INVENTORY_PATH:-$lab/config/upstream-inventory.json}"
command -v jq >/dev/null 2>&1 || { echo "needs \`jq\`" >&2; exit 2; }
[ -f "$INVENTORY" ] || { echo "no upstream inventory at $INVENTORY" >&2; exit 2; }

mapfile -t adapters < <(jq -r '.harnesses[]' "$INVENTORY")

# --- the README's verification procedure -------------------------------------
# The procedure is how the user makes the first observation, so its commands
# must work as written — and the suite runs them, against the fake. The
# commands are read OUT of the README, so the document and this check cannot
# drift apart: a procedure that no longer works fails here, not on the
# operator's machine.
readme="$hh/README.md"

# The shared setup block: the fenced bash block that installs the plugin and
# prepares the isolation environment.
procedure_setup() {
  awk '
    /^[ \t]*```bash[ \t]*$/ { inblock = 1; buf = ""; next }
    /^[ \t]*```[ \t]*$/ {
      if (inblock) {
        if (buf ~ /adapter_install/) { printf "%s", buf; exit }
        inblock = 0
      }
      next
    }
    inblock { buf = buf $0 "\n" }
  ' "$readme"
}

# The command for one harness: the second cell of its row in the procedure's
# table. The table marks its rows with the harness name in backticks, so it
# is not confused with the provenance table above it.
procedure_command() { # $1 harness
  awk -v h="$1" '
    index($0, "| `" h "` |") == 1 {
      line = $0
      sub(/^[^|]*\|[^|]*\|/, "", line)
      sub(/\|.*$/, "", line)
      gsub(/`/, "", line)
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      print line
      exit
    }
  ' "$readme"
}

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
# cli:     the name the CLI answers to — the fake is installed under it, and
#          it is the only agent CLI the adapter may reach
expect() { # $1 harness  $2 key
  case "$1/$2" in
    antigravity/skill) echo "using-sdlc-skills";;
    antigravity/install) echo "agy plugin install";;
    antigravity/launch) echo "agy";;
    antigravity/usage) echo "125";;
    antigravity/resume) echo "yes";;
    antigravity/tier) echo "no";;
    antigravity/cli) echo "agy";;
    antigravity/seed) echo "no";;
    claude-code/skill) echo "using-sdlc-skills";;
    claude-code/install) echo "";;
    claude-code/launch) echo "claude";;
    claude-code/usage) echo "165";;
    claude-code/resume) echo "yes";;
    claude-code/tier) echo "yes";;
    claude-code/cli) echo "claude";;
    claude-code/seed) echo "yes";;
    codex/skill) echo "sdlc-skills:using-sdlc-skills";;
    codex/install) echo "codex plugin marketplace add";;
    codex/launch) echo "codex exec";;
    codex/usage) echo "60";;
    codex/resume) echo "yes";;
    codex/tier) echo "no";;
    codex/cli) echo "codex";;
    codex/seed) echo "yes";;
    cursor/skill) echo "using-sdlc-skills";;
    cursor/install) echo "";;
    cursor/launch) echo "cursor-agent";;
    cursor/usage) echo "-";;
    cursor/resume) echo "yes";;
    cursor/tier) echo "no";;
    cursor/cli) echo "cursor-agent";;
    cursor/seed) echo "yes";;
    devin/skill) echo "using-sdlc-skills";;
    devin/install) echo "devin plugins install";;
    devin/launch) echo "devin";;
    devin/usage) echo "81";;
    devin/resume) echo "yes";;
    devin/tier) echo "no";;
    devin/cli) echo "devin";;
    devin/seed) echo "yes";;
    grok/skill) echo "using-sdlc-skills";;
    grok/install) echo "grok plugin install";;
    grok/launch) echo "grok";;
    grok/usage) echo "120";;
    grok/resume) echo "no";;
    grok/tier) echo "no";;
    grok/cli) echo "grok";;
    grok/seed) echo "yes";;
    hermes/skill) echo "sdlc-skills:using-sdlc-skills";;
    hermes/install) echo "hermes plugins install";;
    hermes/launch) echo "hermes";;
    hermes/usage) echo "102";;
    hermes/resume) echo "yes";;
    hermes/tier) echo "no";;
    hermes/cli) echo "hermes";;
    hermes/seed) echo "yes";;
    kimi-code/skill) echo "sdlc-skills:using-sdlc-skills";;
    kimi-code/install) echo "";;
    kimi-code/launch) echo "kimi";;
    kimi-code/usage) echo "-";;
    kimi-code/resume) echo "yes";;
    kimi-code/tier) echo "no";;
    kimi-code/cli) echo "kimi";;
    kimi-code/seed) echo "yes";;
    muse/skill) echo "using-sdlc-skills";;
    muse/install) echo "";;
    muse/launch) echo "muse exec";;
    muse/usage) echo "90";;
    muse/resume) echo "yes";;
    muse/tier) echo "no";;
    muse/cli) echo "muse";;
    muse/seed) echo "yes";;
    opencode/skill) echo "using-git-worktrees";;
    opencode/install) echo "";;
    opencode/launch) echo "opencode run";;
    opencode/usage) echo "100";;
    opencode/resume) echo "yes";;
    opencode/tier) echo "no";;
    opencode/cli) echo "opencode";;
    opencode/seed) echo "yes";;
    pi/skill) echo "using-sdlc-skills";;
    pi/install) echo "pi install";;
    pi/launch) echo "pi";;
    pi/usage) echo "120";;
    pi/resume) echo "yes";;
    pi/tier) echo "no";;
    pi/cli) echo "pi";;
    pi/seed) echo "yes";;
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

  # --- the operator's own variables, as sentinels ----------------------------
  # Each one is set to a path inside this test's work directory, so it is
  # neither the operator's real value nor a value any CLI could want. An
  # adapter that inherits the operator's environment hands these to its CLI,
  # and the assertions below catch exactly that.
  local op="$work/operator" sentinels="$work/sentinels"
  mkdir -p "$op"
  : > "$sentinels"
  local ovar
  for ovar in $OPERATOR_VARS; do
    case "$ovar" in
      *_AUTO_UPDATE|*DISABLE_AUTOUPDATER) export "$ovar=operator-sentinel";;
      DBUS_SESSION_BUS_ADDRESS) export "DBUS_SESSION_BUS_ADDRESS=unix:path=$op/.bus";;
      *) export "$ovar=$op/$ovar";;
    esac
    printf '%s\n' "${!ovar}" >> "$sentinels"
  done

  # --- the real CLIs are not reachable: PROVED, not assumed -----------------
  # Every agent CLI name must resolve into the fake's own bin directory. A
  # real CLI of the same name that shadowed the fake — a PATH built the
  # other way round, or an operator's bin directory ahead of the fake's —
  # fails here, loudly, instead of being launched.
  local cli resolved shadowed=""
  for cli in $CLI_NAMES; do
    resolved="$(command -v "$cli" 2>/dev/null)"
    case "$resolved" in
      "$bin/$cli") ;;
      *) shadowed="$shadowed $cli(${resolved:-none})";;
    esac
  done
  if [ -z "$shadowed" ]; then
    ok "every agent CLI name resolves into the fake's bin directory"
  else
    bad "every agent CLI name resolves into the fake's bin directory — not the fake:$shadowed"
  fi

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
  local green_home="$harness_home"
  local calls; calls="$(cat "$log" 2>/dev/null; cat "$harness_home/.fake-harness.log" 2>/dev/null)"
  if [ -z "$install_pattern" ]; then
    ok "$h install needs no CLI invocation"
  elif printf '%s\n' "$calls" | grep -qF -- "$install_pattern"; then
    ok "$h install invokes the CLI ($install_pattern)"
  else
    bad "$h install invokes the CLI ($install_pattern) — log: $(printf '%s\n' "$calls" | grep '^call ' | tr '\n' '|')"
  fi

  # --- the version probe is an invocation too --------------------------------
  # A version check is a CLI invocation, and it must run under the same
  # closed environment as the launches. With neither a runtime directory nor
  # a bus address of its own, a D-Bus client in the probe falls back to the
  # passwd entry's runtime directory — the operator's own session bus — which
  # is the one route a "throwaway HOME" does not close.
  #
  # So the probe runs in the throwaway home the adapter built, and its own
  # record is visible there. opencode is the only adapter that probes a
  # version; the other ten make no such call.
  if [ "$h" = "opencode" ]; then
    local probe_log="$green_home/.fake-harness.log"
    if grep -q '^call opencode --version' "$probe_log" 2>/dev/null &&
       grep -q "^env opencode HOME=$green_home\$" "$probe_log" 2>/dev/null &&
       grep -q "^env opencode XDG_RUNTIME_DIR=$green_home/" "$probe_log" 2>/dev/null &&
       grep -q "^env opencode DBUS_SESSION_BUS_ADDRESS=unix:path=$green_home/" "$probe_log" 2>/dev/null; then
      ok "opencode the version probe runs under the throwaway home"
    else
      bad "opencode the version probe runs under the throwaway home"
    fi
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
  # The none arm's STATE, not the absence of a CLI call: a none arm that
  # installed a plugin would measure the plugin, silently. So the throwaway
  # home must hold no plugin tree and no registry that names the tree under
  # test, the commands that ran must name neither, and the adapter must
  # leave no plugin path behind — a stale `plugin_dir` from the green arm
  # is a plugin the none arm would load.
  local none_leak="" none_found
  none_found="$(find "$harness_home" \( -name 'sdlc-skills' -o -name 'SKILL.md' \) \
    -print -quit 2>/dev/null || true)"
  [ -n "$none_found" ] && none_leak="$none_leak plugin-tree"
  none_found="$(grep -rlF -- "$plug" "$harness_home" 2>/dev/null | head -1 || true)"
  [ -n "$none_found" ] && none_leak="$none_leak registry"
  printf '%s\n' "$none_calls" | grep -qF -- "$plug" && none_leak="$none_leak command"
  if [ -n "$install_pattern" ] && printf '%s\n' "$none_calls" | grep -qF -- "$install_pattern"; then
    none_leak="$none_leak install-command"
  fi
  [ -n "${plugin_dir:-}" ] && none_leak="$none_leak plugin-dir"
  if [ -z "$none_leak" ]; then
    ok "$h none arm installs no plugin"
  else
    bad "$h none arm installs no plugin ($none_leak )"
  fi

  # --- the launch ------------------------------------------------------------
  : > "$log"
  printf 'fake stdout\n' > "$work/fake-stdout"
  cp "$work/fake-stdout" "$HOME/.fake-stdout"
  export FAKE_STDOUT="$work/fake-stdout"
  printf 'the opening\n' > "$work/opening"
  # The operator's credential seed, as a stand-in: the runner exports
  # $LAB_CREDENTIAL_SEED/<harness>/env for a harness whose auth is
  # environmental, and the launch has to carry it — the environment is
  # built explicitly, so a seed that is not carried is a run with no
  # credential. The stand-in switches the fake's seed probe on, so the
  # seed's arrival is visible in the fake's own log.
  mkdir -p "$work/seed/$h"
  printf 'LAB_SEED_PROBE=1\n' > "$work/seed/$h/env"
  export LAB_CREDENTIAL_SEED="$work/seed"
  if adapter_run_activation "$wd" "the prompt" "$stream" >/dev/null 2>"$work/run.err"; then
    ok "$h activation launch succeeds against the fake CLI"
  else
    bad "$h activation launch succeeds against the fake CLI (see $work/run.err)"
  fi
  local seed_log="$work/seed.log" seed_cli
  seed_cli="$(expect "$h" cli)"
  cat "$log" 2>/dev/null > "$seed_log"
  cat "$harness_home/.fake-harness.log" 2>/dev/null >> "$seed_log"
  if [ "$(expect "$h" seed)" = "yes" ]; then
    if grep -qx "seed $seed_cli" "$seed_log" 2>/dev/null; then
      ok "$h the launch carries the operator's credential seed"
    else
      bad "$h the launch carries the operator's credential seed"
    fi
  else
    if grep -qx "seed $seed_cli" "$seed_log" 2>/dev/null; then
      bad "$h the launch carries no credential (this harness has none by design)"
    else
      ok "$h the launch carries no credential (this harness has none by design)"
    fi
  fi
  local launch_pattern; launch_pattern="$(expect "$h" launch)"
  local launch_calls; launch_calls="$(cat "$log" 2>/dev/null; cat "$harness_home/.fake-harness.log" 2>/dev/null)"
  if printf '%s\n' "$launch_calls" | grep -qF -- "$launch_pattern"; then
    ok "$h activation launch reaches the CLI ($launch_pattern)"
  else
    bad "$h activation launch reaches the CLI ($launch_pattern) — log: $(printf '%s\n' "$launch_calls" | grep '^call ' | tr '\n' '|')"
  fi
  if [ -s "$stream" ]; then
    ok "$h activation launch captures the CLI's output"
  else
    bad "$h activation launch captures the CLI's output"
  fi
  # the run that follows the none-arm install reports no skill
  got="$(adapter_chain "$stream" 2>/dev/null)"
  if [ -z "$got" ]; then
    ok "$h the none arm's run reports no skill"
  else
    bad "$h the none arm's run reports no skill (got '$got')"
  fi
  if adapter_run_behavioral "$wd" "$work/opening" "$stream" >/dev/null 2>"$work/beh.err"; then
    ok "$h behavioural launch succeeds against the fake CLI"
  else
    bad "$h behavioural launch succeeds against the fake CLI (see $work/beh.err)"
  fi
  unset FAKE_STDOUT

  # --- which CLI answered, and what it was handed ---------------------------
  # The fake logs to $FAKE_HARNESS_LOG when the environment carries it, and to
  # $HOME/.fake-harness.log when it does not: several adapters launch their
  # CLI with a cleared environment, and the log has to survive that. Both
  # sources are read here, in one file, so the assertions below see every
  # call the adapter made.
  cat "$log" 2>/dev/null > "$work/all.log"
  cat "$harness_home/.fake-harness.log" 2>/dev/null >> "$work/all.log"
  # The fake records three things per invocation: the call, the RESOLVED path
  # of the binary that answered, and the environment it was launched with.
  # Together they are the proof that the CLI the adapter reached is the fake
  # in this test's bin directory, and that no other agent CLI was reached.
  local want_cli; want_cli="$(expect "$h" cli)"
  local called; called="$(awk '/^call /{print $2}' "$work/all.log" 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ "$called" = "$want_cli " ]; then
    ok "$h reached only $want_cli, and nothing else"
  else
    bad "$h reached only $want_cli, and nothing else (reached: ${called:-none})"
  fi
  if awk -v b="$bin/" '/^at /{ if (index($3, b) == 1) found = 1 } END { exit !found }' "$work/all.log"; then
    ok "$h the CLI that answered is the fake in this test's bin directory"
  else
    bad "$h the CLI that answered is the fake in this test's bin directory"
  fi

  # --- the operator's own credential is out of reach -------------------------
  # The throwaway home holds no credential — the fake writes none — so the
  # only credential a launch could use is the operator's. A CLI that is
  # pointed at a directory inside the operator's home is therefore a run that
  # can read the operator's token, so none of the variables a CLI keeps its
  # home in may point there.
  #
  # The environment of EVERY invocation the adapter made, read from the
  # fake's own log: the install's invocations and the launches alike. The
  # order of the log does not matter — an adapter that isolates one
  # invocation and not the other has left a hole, and the assertions below
  # read the whole set.
  local envlines="$work/env.txt"
  awk '/^call /{ if (n) { for (i = 1; i <= n; i++) print e[i] }
          n = 0; delete e }
       /^env /{ e[++n] = $0 }
       END { if (n) { for (i = 1; i <= n; i++) print e[i] } }' \
    "$work/all.log" > "$envlines" 2>/dev/null || true
  # Every throwaway home the adapter built: the green arm's and the none
  # arm's. A directory the CLI was handed must be inside one of them.
  local homes="$work/homes"
  : > "$homes"
  printf '%s\n' "$green_home" "$harness_home" >> "$homes"
  local launched_home
  launched_home="$(sed -n "s/^env $want_cli HOME=//p" "$envlines" | tail -1)"
  if [ -n "$launched_home" ] && [ "$launched_home" != "$OPERATOR_HOME" ]; then
    ok "$h the CLI ran with a home that is not the operator's"
  else
    bad "$h the CLI ran with a home that is not the operator's (HOME=${launched_home:-none})"
  fi
  # The WHOLE recorded environment, not a fixed list of nine names: any
  # variable the CLI was handed that carries the operator's home, their
  # XDG directories, their session bus or their updater switch is a route
  # back to the operator. The sentinels are this test's own values, so a
  # leak is caught whether or not the developer exports anything.
  local leaks="" lkey lval
  while IFS= read -r lline; do
    lkey="${lline%%=*}"
    lval="${lline#*=}"
    case "$lval" in
      "$OPERATOR_HOME"|"$OPERATOR_HOME"/*) leaks="$leaks $lkey(operator-home)"; continue;;
    esac
    if grep -qxF -- "$lval" "$sentinels" 2>/dev/null; then
      leaks="$leaks $lkey(operator-value)"
    fi
  done < <(sed -n "s/^env $want_cli //p" "$envlines" 2>/dev/null)
  if [ -z "$leaks" ]; then
    ok "$h no home the CLI was given points into the operator's home"
  else
    bad "$h no home the CLI was given points into the operator's home (leaks:$leaks)"
  fi
  # The session bus: an address that points at the operator's is a route to
  # the operator's stored credentials, and so is a runtime directory that
  # points at the operator's — with no address set, a D-Bus client looks for
  # the bus under the runtime directory. So every invocation must be given a
  # runtime directory inside a throwaway home, and a bus address (if it
  # carries one) inside one too.
  if grep -qF -- "$op/.bus" "$envlines" 2>/dev/null ||
     { [ -n "$OPERATOR_DBUS" ] && grep -qF -- "$OPERATOR_DBUS" "$envlines" 2>/dev/null; }; then
    bad "$h the launch cannot reach the operator's session bus"
  else
    ok "$h the launch cannot reach the operator's session bus"
  fi
  local runtime_dir runtime_ok=1
  while IFS= read -r runtime_dir; do
    [ -n "$runtime_dir" ] || continue
    grep -qxF -- "$runtime_dir" "$homes" >/dev/null 2>&1 && continue
    case "$runtime_dir" in
      "$harness_home"/*) continue;;
    esac
    runtime_ok=0
  done < <(sed -n "s/^env $want_cli XDG_RUNTIME_DIR=//p" "$envlines" 2>/dev/null)
  if [ "$runtime_ok" -eq 1 ] && [ -n "$(sed -n "s/^env $want_cli XDG_RUNTIME_DIR=//p" "$envlines" | head -1)" ]; then
    ok "$h the launch's runtime dir is inside the throwaway home"
  else
    bad "$h the launch's runtime dir is inside the throwaway home"
  fi
  local bus_addr bus_ok=1
  while IFS= read -r bus_addr; do
    [ -n "$bus_addr" ] || continue
    case "${bus_addr#unix:path=}" in
      "$harness_home"/*) continue;;
      *) bus_ok=0;;
    esac
  done < <(sed -n "s/^env $want_cli DBUS_SESSION_BUS_ADDRESS=//p" "$envlines" 2>/dev/null)
  if [ "$bus_ok" -eq 1 ]; then
    ok "$h the launch's session bus address is inside the throwaway home"
  else
    bad "$h the launch's session bus address is inside the throwaway home"
  fi
  if [ "$h" = "antigravity" ]; then
    # The CLI writes into ~/.gemini/, so the isolation has to hold for the
    # directories it uses, and the self-updater has to be off.
    local agy_dirs_ok=1
    for key in XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS; do
      val="$(sed -n "s/^env $want_cli $key=//p" "$envlines" | tail -1)"
      val="${val#unix:path=}"
      case "$val" in
        "$harness_home"/*) ;;
        *) agy_dirs_ok=0;;
      esac
    done
    if [ "$agy_dirs_ok" -eq 1 ]; then
      ok "antigravity every directory the CLI uses is inside the throwaway home"
    else
      bad "antigravity every directory the CLI uses is inside the throwaway home"
    fi
    if grep -qx "env $want_cli AGY_CLI_DISABLE_AUTO_UPDATE=true" "$envlines"; then
      ok "antigravity the self-updater is disabled"
    else
      bad "antigravity the self-updater is disabled"
    fi
  fi

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

  # the refusal: the model never spoke. Every adapter must be able to tell
  # a refusal from a miss: without adapter_ran the runner cannot, and a
  # provider that never answered is scored as an ordinary miss.
  printf '{"type":"error","error":{"message":"usage limit exceeded"}}\n' > "$work/refusal.jsonl"
  if command -v adapter_ran >/dev/null 2>&1; then
    ok "$h binds adapter_ran (the runner tells a refusal from a miss)"
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
    bad "$h binds no adapter_ran (a provider refusal would be scored as a miss)"
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

  # --- devin's resume is a resume, not a fresh session ------------------------
  # The contract: a continue resumes from the session the prior stream
  # records, never a fresh session. Devin speaks ACP, so the resume is an
  # ACP session/load (or session/resume) for the recorded id — and the
  # fake's own record of what it was asked for is the proof. A continue that
  # quietly opened a new session would be scored as a resume, so the record
  # is read, not the adapter's word.
  if [ "$h" = "devin" ]; then
    local prior_sid acp_log acp_before turn_log
    prior_sid="$(jq -r 'select(.id? == 2) | .result.sessionId // empty' "$stream" 2>/dev/null | head -1)"
    acp_log="$harness_home/.fake-harness.log"
    # Only the records the CONTINUE made count: the runs before it asked
    # for their own sessions, and a grep over the whole log would match
    # them.
    acp_before="$(wc -l < "$acp_log" 2>/dev/null || echo 0)"
    if [ -n "$prior_sid" ] && adapter_continue_behavioral "$wd" "next" "$work/next.jsonl" "$stream" \
        >/dev/null 2>"$work/resume.err"; then
      ok "devin continues a session it can identify ($prior_sid)"
    else
      bad "devin continues a session it can identify ($prior_sid) (see $work/resume.err)"
    fi
    turn_log="$work/acp-turn.log"
    tail -n "+$((acp_before + 1))" "$acp_log" > "$turn_log" 2>/dev/null || : > "$turn_log"
    if grep -q '^acp devin .*"method":"session/new"' "$turn_log" 2>/dev/null; then
      bad "devin opens no fresh session for a continue (it sent session/new)"
    else
      ok "devin opens no fresh session for a continue"
    fi
    if grep -q "^acp devin .*\"method\":\"session/load\".*$prior_sid" "$turn_log" 2>/dev/null ||
       grep -q "^acp devin .*\"method\":\"session/resume\".*$prior_sid" "$turn_log" 2>/dev/null; then
      ok "devin loads the session the prior stream recorded"
    else
      bad "devin loads the session the prior stream recorded ($prior_sid)"
    fi
    if grep -q "^acp devin .*\"method\":\"session/prompt\".*$prior_sid" "$turn_log" 2>/dev/null; then
      ok "devin prompts the session the prior stream recorded"
    else
      bad "devin prompts the session the prior stream recorded ($prior_sid)"
    fi
    # An agent that advertises no resume capability cannot resume: the
    # continue must be refused, not answered by a fresh session.
    printf 'none\n' > "$bin/acp-caps"
    if adapter_continue_behavioral "$wd" "next" "$work/next2.jsonl" "$stream" \
        >/dev/null 2>"$work/resume2.err"; then
      bad "devin refuses a continue its ACP server cannot resume"
    else
      ok "devin refuses a continue its ACP server cannot resume"
    fi
    # The other way ACP v1 offers to resume: the agent advertises
    # sessionCapabilities.resume instead of loadSession.
    printf 'resume\n' > "$bin/acp-caps"
    acp_before="$(wc -l < "$acp_log" 2>/dev/null || echo 0)"
    if adapter_continue_behavioral "$wd" "next" "$work/next3.jsonl" "$stream" \
        >/dev/null 2>"$work/resume3.err"; then
      ok "devin resumes through session/resume where the agent advertises it"
    else
      bad "devin resumes through session/resume where the agent advertises it (see $work/resume3.err)"
    fi
    tail -n "+$((acp_before + 1))" "$acp_log" > "$turn_log" 2>/dev/null || : > "$turn_log"
    if grep -q "^acp devin .*\"method\":\"session/resume\".*$prior_sid" "$turn_log" 2>/dev/null &&
       ! grep -q '^acp devin .*"method":"session/new"' "$turn_log" 2>/dev/null; then
      ok "devin resumes the recorded session through session/resume"
    else
      bad "devin resumes the recorded session through session/resume"
    fi
    rm -f "$bin/acp-caps"
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

  # --- the verification procedure's own commands -----------------------------
  # The README's procedure is how the user makes the first observation. A
  # procedure whose commands fail is not a procedure, so the suite runs them,
  # against the fake: the commands are read out of the README, so the
  # document and this check cannot drift apart.
  local setup prep cmd_line setup_ok=0
  setup="$(procedure_setup)"
  cmd_line="$(procedure_command "$h")"
  if [ -z "$setup" ]; then
    bad "$h the README names no procedure to run"
  else
    # The procedure's own paths: the lab checkout and the plugin checkout are
    # the operator's, and here they are the lab's and the fake plugin tree.
    prep="$(printf '%s\n' "$setup" \
      | sed -e "s|/path/to/sdlc-skills-evals|$lab|g" \
            -e "s|<harness>|$h|g" \
            -e "s|/path/to/sdlc-skills|$plug|g")"
    # The procedure must provide the globals the adapter reads, so they are
    # taken away first: the test's own values would otherwise answer for a
    # procedure that forgot them, and a user in a fresh shell would not have
    # them at all.
    unset errlog timeout_s
    if eval "$prep" >/dev/null 2>"$work/proc-setup.err"; then
      setup_ok=1
      ok "$h the procedure's setup block succeeds"
    else
      bad "$h the procedure's setup block succeeds (see $work/proc-setup.err)"
    fi
    if [ -n "${errlog:-}" ] && [ -n "${timeout_s:-}" ]; then
      ok "$h the procedure's setup block provides the globals the adapter reads"
    else
      bad "$h the procedure's setup block provides the globals the adapter reads"
    fi
    if [ -z "$cmd_line" ]; then
      bad "$h the README names no command for the procedure"
    elif [ "$setup_ok" -eq 0 ]; then
      bad "$h the procedure's command succeeds (the setup block did not run)"
    else
      if eval "$cmd_line" >/dev/null 2>"$work/proc-run.err"; then
        ok "$h the procedure's command succeeds"
      else
        bad "$h the procedure's command succeeds (see $work/proc-run.err)"
      fi
      if [ -s "$stream" ]; then
        ok "$h the procedure's command writes the stream"
      else
        bad "$h the procedure's command writes the stream"
      fi
      # The command must reach the CLI through the adapter, under the
      # isolation environment the adapter builds: a command run outside it
      # would inherit the operator's session bus and their credential
      # helpers, which is the whole reason the procedure uses the adapter.
      local proc_log proc_ok=1
      proc_log="$harness_home/.fake-harness.log"
      grep -q "^env $want_cli HOME=$harness_home\$" "$proc_log" 2>/dev/null || proc_ok=0
      grep -q "^env $want_cli XDG_RUNTIME_DIR=$harness_home/" "$proc_log" 2>/dev/null || proc_ok=0
      if [ "$proc_ok" -eq 1 ]; then
        ok "$h the procedure's command runs the CLI under the isolation environment"
      else
        bad "$h the procedure's command runs the CLI under the isolation environment"
      fi
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
