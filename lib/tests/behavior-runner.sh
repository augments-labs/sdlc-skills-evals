#!/usr/bin/env bash
# Offline test: bin/behavior — its outcome classes, the plans it prints,
# and the offline paths that must launch nothing.
#
# Every run here uses the fake harness (--harness-dir lib/tests/fake-cli
# with --scenario-dir lib/tests/fake-cli/scenarios), so no agent CLI is
# reached and no token is spent. The non-launching cases put a SENTINEL
# real CLI on PATH — one that fails and records the call — and the
# live-path control that follows proves the sentinel is reachable at all.
# Two cases read a real adapter's header without launching it: the
# unrunnable-harness dry run, and the control above.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
fake_s="$fake_h/scenarios"
export SDLC_SKILLS_EVALS_ROOT="$here"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

# a throwaway plugin stand-in for --plugin (a real git checkout, no sibling needed)
standin="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$standin" "$work"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

# the pin a run resolves when the caller names none
inv_commit="$(jq -r '.upstream.commit' "$here/config/upstream-inventory.json")"

run() { # runs bin/behavior, prints exit code on stdout, suppresses output
  "$here/bin/behavior" "$@" >/dev/null 2>&1; printf '%s' "$?"
}

t() { # $1 expected-exit $2 description $3... behavior args
  local want="$1" desc="$2"; shift 2
  local got
  got="$(run "$@")"
  if [ "$got" = "$want" ]; then ok "$desc";
  else bad "$desc (exit $got, want $want)"; fi
}

base=(--harness-dir "$fake_h" --scenario-dir "$fake_s")

t 0 "help exits 0" --help
t 2 "arm none rejects --plugin" --harness fake --scenario probe-ok --arm none --plugin "$standin" "${base[@]}"
# (the unavailable probe needs an env assignment: run directly)
got="$(FAKE_UNAVAILABLE=1 "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "unavailable harness exits 2" || bad "unavailable harness exits 2 (got $got)"

t 0 "green ok run passes" \
  --harness fake --scenario probe-ok --arm green --plugin "$standin" "${base[@]}"
t 2 "none arm with a chain is contaminated" \
  --harness fake --scenario probe-ok --arm none "${base[@]}"
got="$(FAKE_CHAIN=0 "$here/bin/behavior" --harness fake --scenario probe-ok --arm none "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 0 ] && ok "clean none arm passes" || bad "clean none arm passes (got $got)"
t 2 "red arm needs --base" \
  --harness fake --scenario probe-ok --arm red --plugin "$standin" "${base[@]}"
got="$(FAKE_MODE=timeout "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" --timeout 2 "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "timeout exits 2" || bad "timeout exits 2 (got $got)"
got="$(FAKE_MODE=error "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "adapter error exits 2" || bad "adapter error exits 2 (got $got)"
got="$(FAKE_MODE=blocked "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "provider refusal exits 2" || bad "provider refusal exits 2 (got $got)"
got="$(FAKE_MODE=dead "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "empty capture exits 2" || bad "empty capture exits 2 (got $got)"
got="$("$here/bin/behavior" --harness fake --scenario probe-nochecks --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1; printf '%s' "$?")"
[ "$got" = 2 ] && ok "no checks run exits 2" || bad "no checks run exits 2 (got $got)"
t 0 "tier override passes through" \
  --harness fake --scenario probe-ok --arm green --plugin "$standin" --tier small "${base[@]}"

# --record writes the run file with the frozen keys
rec="$(mktemp -d)"
"$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" \
  --record "$rec" "${base[@]}" >/dev/null 2>&1
f="$rec/runs/probe-ok-green-1.json"
[ -f "$f" ] && ok "record file written" || bad "record file written"
if [ -f "$f" ]; then
  jq -e --arg c "$plug_commit" \
    '.scenario == "probe-ok" and .arm == "green" and .harness == "fake"
     and .plugin_commit == $c and .verdict == "pass" and .stage == null
     and (.checks_run | type == "number") and .checks_run >= 1
     and .tokens == null and (.duration_ms | type == "number")
     and (.workdir | type == "string")' "$f" >/dev/null \
    && ok "record carries the frozen keys" || bad "record carries the frozen keys"
fi
rm -rf "$rec"

# --- the non-launching paths -------------------------------------------------
#
# A sentinel real CLI stands on PATH: it fails and records that it was
# called. The help and the dry run must never reach it — a plan that
# launched a CLI would spend a token to say what it planned.

sentinel_log="$work/sentinel.log"
sentinel_dir="$work/sentinel"
mkdir -p "$sentinel_dir"
for cli in opencode claude codex kimi; do
  cat >"$sentinel_dir/$cli" <<SENTINEL
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$sentinel_log"
exit 1
SENTINEL
  chmod +x "$sentinel_dir/$cli"
done
PATH="$sentinel_dir:$PATH"; export PATH

out="$("$here/bin/behavior" --help 2>&1)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "help names the pinned commit" || bad "help names the pinned commit"

out="$("$here/bin/behavior" --harness opencode --scenario probe-ok --arm green \
  --scenario-dir "$fake_s" --dry-run 2>&1)"
rc="$?"
[ "$rc" -eq 0 ] && ok "the dry run exits 0" || bad "the dry run exits 0 (exit $rc)"
printf '%s' "$out" | grep -qF "pin        : $inv_commit" \
  && ok "the dry run names the pin" || bad "the dry run names the pin"
printf '%s' "$out" | grep -qF "command    : bin/behavior --harness opencode --scenario probe-ok --arm green --plugin $inv_commit" \
  && ok "the dry run names the exact planned invocation" \
  || bad "the dry run names the exact planned invocation"
printf '%s' "$out" | grep -qF -- "--timeout 1800" \
  && ok "the dry run names the timeout the run would use" \
  || bad "the dry run names the timeout the run would use"

# the dry run refuses what the live run refuses
"$here/bin/behavior" --harness opencode --scenario probe-ok --arm none --plugin "$standin" \
  --scenario-dir "$fake_s" --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "the dry run refuses --arm none with --plugin" \
  || bad "the dry run refuses --arm none with --plugin"
"$here/bin/behavior" --harness opencode --scenario no-such-scenario --arm green \
  --scenario-dir "$fake_s" --dry-run >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "the dry run refuses a missing scenario" \
  || bad "the dry run refuses a missing scenario"

# the dry run reaches neither a real CLI nor the fake launcher
launch_log="$work/launch.log"
rm -f "$launch_log"
FAKE_LAUNCH_LOG="$launch_log" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --plugin "$standin" --dry-run "${base[@]}" >/dev/null 2>&1
[ ! -f "$launch_log" ] && ok "the dry run does not reach the fake launcher" \
  || bad "the dry run does not reach the fake launcher"
[ ! -f "$sentinel_log" ] && ok "help and the dry run call no CLI" \
  || bad "help and the dry run call no CLI (the sentinel was called)"

# the control: the live path DOES reach the CLI, so the case above is not
# vacuous. The sentinel fails, so nothing is spent and the run is
# indeterminate.
"$here/bin/behavior" --harness opencode --scenario probe-ok --arm green \
  --plugin "$standin" --scenario-dir "$fake_s" >/dev/null 2>&1
[ -f "$sentinel_log" ] && ok "the live path reaches the CLI (the control)" \
  || bad "the live path reaches the CLI (the control)"

# --- a user-invoked run still reaches the fake launcher ----------------------
#
# The live path is the user's to operate; the fake stands in for the agent
# CLI, and a run that never reaches it measures nothing.

rm -f "$launch_log"
FAKE_LAUNCH_LOG="$launch_log" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --plugin "$standin" "${base[@]}" >/dev/null 2>&1
[ -f "$launch_log" ] && ok "a user-invoked run reaches the fake launcher" \
  || bad "a user-invoked run reaches the fake launcher"

# --- pinning ----------------------------------------------------------------
#
# A run pinned by commit resolves that commit and records it: the pin is
# the commit, never a ref that could move.

rec2="$(mktemp -d)"
install_log="$work/install.log"
rm -f "$install_log"
SDLC_SKILLS_ROOT="$standin" FAKE_LAUNCH_LOG="$install_log" \
  "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --plugin "$plug_commit" --record "$rec2" "${base[@]}" >/dev/null 2>&1
f2="$rec2/runs/probe-ok-green-1.json"
if [ -f "$f2" ]; then
  ok "a run pinned by commit is recorded"
  jq -e --arg c "$plug_commit" '.plugin_commit == $c and .verdict == "pass"' "$f2" >/dev/null \
    && ok "the record carries the pinned commit" || bad "the record carries the pinned commit"
else
  bad "a run pinned by commit is recorded"
fi
# the tree the run INSTALLED is the tree the pin names: a run can pin
# the right commit, record the right commit, and measure another tree
green_install="$(sed -n 's/^install //p' "$install_log" 2>/dev/null | head -1)"
green_head="$(sed -n 's/^install-head //p' "$install_log" 2>/dev/null | head -1)"
if [ "$green_head" = "$plug_commit" ]; then
  ok "the run installs the tree the pin names"
else
  bad "the run installs the tree the pin names (installed '$green_install' at '$green_head')"
fi
if [ -n "$green_install" ] && [ "$green_install" != "$standin" ]; then
  ok "the run does not install the moving checkout"
else
  bad "the run does not install the moving checkout (installed '$green_install')"
fi
if [ -f "$f2" ]; then
  jq -e --arg c "$green_head" '.plugin_commit == $c' "$f2" >/dev/null \
    && ok "the record and the installed tree agree" || bad "the record and the installed tree agree"
else
  bad "the record and the installed tree agree (no record)"
fi
rm -rf "$rec2"

# the red arm installs the BASE's tree: the two arms measure two trees
base_repo="$work/baserepo"
mkdir -p "$base_repo"
git -C "$base_repo" init -q
git -C "$base_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
base_commit="$(git -C "$base_repo" rev-parse HEAD)"
rec2b="$(mktemp -d)"
red_log="$work/redinstall.log"
rm -f "$red_log"
SDLC_SKILLS_ROOT="$base_repo" FAKE_LAUNCH_LOG="$red_log" \
  "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm red --base "$base_commit" --record "$rec2b" "${base[@]}" >/dev/null 2>&1
red_install="$(sed -n 's/^install //p' "$red_log" 2>/dev/null | head -1)"
red_head="$(sed -n 's/^install-head //p' "$red_log" 2>/dev/null | head -1)"
if [ "$red_head" = "$base_commit" ]; then
  ok "the red arm installs the base's tree"
else
  bad "the red arm installs the base's tree (installed '$red_install' at '$red_head')"
fi
if [ -n "$red_install" ] && [ "$red_install" != "$green_install" ] \
   && [ "$red_head" != "$green_head" ]; then
  ok "the green and the red arm install two different trees"
else
  bad "the green and the red arm install two different trees (green '$green_install' at '$green_head', red '$red_install' at '$red_head')"
fi
rm -rf "$rec2b"

# the default pin is the committed one, and a run that cannot resolve it
# says so instead of running something else
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm green \
  --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $inv_commit" \
  && ok "the default pin is the committed one" || bad "the default pin is the committed one"

# a directory plugin is named as the tree it is: a working tree is not a
# commit, and calling it one would describe content the run never measured
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm green \
  --plugin "$standin" --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $standin" \
  && ok "the dry run names the tree a directory plugin installs" \
  || bad "the dry run names the tree a directory plugin installs"
SDLC_SKILLS_ROOT="$standin" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green "${base[@]}" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a run that cannot resolve the default pin refuses" \
  || bad "a run that cannot resolve the default pin refuses"

# an inventory that names no commit is refused, and NO tree is named in
# its place: the runner falls back to nothing, never to some other tree
broken_inv="$work/no-commit-inventory.json"
jq '.upstream.commit = "v11.0.0"' "$here/config/upstream-inventory.json" > "$broken_inv"
out="$(INVENTORY_PATH="$broken_inv" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --dry-run "${base[@]}" 2>&1)"
rc="$?"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -qF "no usable upstream pin"; then
  ok "the behaviour runner refuses a default pin it cannot resolve"
else
  bad "the behaviour runner refuses a default pin it cannot resolve (exit $rc, got '$out')"
fi
case "$out" in
  *"pin        :"*) bad "the refusal names no tree in place of the pin";;
  *) ok "the refusal names no tree in place of the pin";;
esac
INVENTORY_PATH="$broken_inv" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green "${base[@]}" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "the live path refuses a default pin it cannot resolve" \
  || bad "the live path refuses a default pin it cannot resolve"

# --- the plan is the whole command, option by option -------------------------
#
# The plan advertises the exact invocation. A prefix match would let a plan
# that drops --record, --tier, --keep or a directory override pass, so the
# whole line is compared.

plan_cmd() { # $1 output — the printed command line and nothing else
  printf '%s\n' "$1" | sed -n 's/^command    : //p'
}

rec3="$(mktemp -d)"
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" \
  --tier small --keep --record "$rec3" --scenario-dir "$fake_s" --harness-dir "$fake_h" \
  --timeout 60 --dry-run 2>&1)"
want="bin/behavior --harness fake --scenario probe-ok --arm green --plugin $standin --timeout 60 --tier small --keep --record $rec3 --scenario-dir $fake_s --harness-dir $fake_h"
if [ "$(plan_cmd "$out")" = "$want" ]; then
  ok "the dry run names the whole planned invocation"
else
  bad "the dry run names the whole planned invocation (got '$(plan_cmd "$out")')"
fi
rm -rf "$rec3"

# --- a ref plugin: the plan names a commit, and the plan installs it --------
#
# A ref moves. The plan resolves it once and its command carries the
# commit it named, so a tag that moves afterwards cannot change what the
# plan installs.

tagrepo="$work/tags"
mkdir -p "$tagrepo"
git -C "$tagrepo" init -q
git -C "$tagrepo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m one
tag_one="$(git -C "$tagrepo" rev-parse HEAD)"
git -C "$tagrepo" tag selftest-plan-tag
git -C "$tagrepo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m two
tag_two="$(git -C "$tagrepo" rev-parse HEAD)"
out="$(SDLC_SKILLS_ROOT="$tagrepo" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --plugin selftest-plan-tag --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $tag_one" \
  && ok "the dry run names the commit a ref resolves to" \
  || bad "the dry run names the commit a ref resolves to"
plan="$(plan_cmd "$out")"
case "$plan" in
  *"--plugin $tag_one"*) ok "the planned command carries the commit, not the ref";;
  *) bad "the planned command carries the commit, not the ref (got '$plan')";;
esac
# the tag moves: the plan's command still installs the commit it named
git -C "$tagrepo" tag -f selftest-plan-tag "$tag_two" >/dev/null 2>&1
rec4="$(mktemp -d)"
( cd "$here" && SDLC_SKILLS_ROOT="$tagrepo" eval "$plan --record '$rec4'" ) >/dev/null 2>&1
if [ -f "$rec4/runs/probe-ok-green-1.json" ]; then
  jq -e --arg c "$tag_one" '.plugin_commit == $c' "$rec4/runs/probe-ok-green-1.json" >/dev/null \
    && ok "the planned command installs the commit it named, not the moved tag" \
    || bad "the planned command installs the commit it named, not the moved tag"
else
  bad "the planned command installs the commit it named, not the moved tag (no record)"
fi
rm -rf "$rec4"

# --- the dry run's other arms -----------------------------------------------
#
# The none arm loads no skills, the red arm loads the base's tree, and an
# unrunnable harness is reported rather than refused.

out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm none --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : (none)" \
  && ok "the dry run's none arm names no plugin" || bad "the dry run's none arm names no plugin"
case "$(plan_cmd "$out")" in
  *--plugin*) bad "the dry run's none arm command carries no --plugin";;
  *) ok "the dry run's none arm command carries no --plugin";;
esac

out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm red --base "$plug_commit" \
  --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $plug_commit" \
  && ok "the dry run's red arm names the base's tree" \
  || bad "the dry run's red arm names the base's tree"
plan="$(plan_cmd "$out")"
case "$plan" in
  *"--base $plug_commit"*) ok "the dry run's red arm command carries --base";;
  *) bad "the dry run's red arm command carries --base (got '$plan')";;
esac
case "$plan" in
  *--plugin*) bad "the dry run's red arm command carries no --plugin";;
  *) ok "the dry run's red arm command carries no --plugin";;
esac

# the red and the none arm name the WHOLE command, option by option, so
# that dropping any option the live path honours turns the case red, and
# so that the options an arm does not carry are asserted to be absent
rec5b="$(mktemp -d)"
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm red --base "$plug_commit" \
  --tier small --keep --record "$rec5b" --scenario-dir "$fake_s" --harness-dir "$fake_h" \
  --timeout 60 --dry-run 2>&1)"
want="bin/behavior --harness fake --scenario probe-ok --arm red --base $plug_commit --timeout 60 --tier small --keep --record $rec5b --scenario-dir $fake_s --harness-dir $fake_h"
if [ "$(plan_cmd "$out")" = "$want" ]; then
  ok "the red arm names the whole planned invocation"
else
  bad "the red arm names the whole planned invocation (got '$(plan_cmd "$out")')"
fi
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm none \
  --tier small --keep --record "$rec5b" --scenario-dir "$fake_s" --harness-dir "$fake_h" \
  --timeout 60 --dry-run 2>&1)"
want="bin/behavior --harness fake --scenario probe-ok --arm none --timeout 60 --tier small --keep --record $rec5b --scenario-dir $fake_s --harness-dir $fake_h"
if [ "$(plan_cmd "$out")" = "$want" ]; then
  ok "the none arm names the whole planned invocation"
else
  bad "the none arm names the whole planned invocation (got '$(plan_cmd "$out")')"
fi
rm -rf "$rec5b"

out="$("$here/bin/behavior" --harness codex --scenario probe-ok --arm green \
  --scenario-dir "$fake_s" --dry-run 2>&1)"
rc="$?"
[ "$rc" -eq 0 ] && ok "the dry run reports an unrunnable harness" \
  || bad "the dry run reports an unrunnable harness (exit $rc)"
printf '%s' "$out" | grep -qF "unrunnable" \
  && ok "the dry run names the unrunnable state" || bad "the dry run names the unrunnable state"

# --- the default pin, end to end --------------------------------------------
#
# The pin a run resolves when the caller names none is the committed
# commit. A stand-in clone that has it, and an inventory that names it,
# make that path observable offline.

default_repo="$work/default-root"
mkdir -p "$default_repo"
git -C "$default_repo" init -q
git -C "$default_repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m pinned
default_commit="$(git -C "$default_repo" rev-parse HEAD)"
default_inv="$work/default-inventory.json"
jq --arg c "$default_commit" '.upstream.commit = $c' "$here/config/upstream-inventory.json" > "$default_inv"
rec5="$(mktemp -d)"
INVENTORY_PATH="$default_inv" SDLC_SKILLS_ROOT="$default_repo" \
  "$here/bin/behavior" --harness fake --scenario probe-ok --arm green --record "$rec5" "${base[@]}" \
  >/dev/null 2>&1
if [ -f "$rec5/runs/probe-ok-green-1.json" ]; then
  jq -e --arg c "$default_commit" '.plugin_commit == $c and .verdict == "pass"' \
    "$rec5/runs/probe-ok-green-1.json" >/dev/null \
    && ok "a live run resolves the default pin end to end" \
    || bad "a live run resolves the default pin end to end"
else
  bad "a live run resolves the default pin end to end (no record)"
fi
rm -rf "$rec5"

# --- no invented monetary cost ----------------------------------------------
#
# The offline paths report the plan, never a price. The pattern is a
# currency symbol followed by a digit, or a three-letter currency code —
# the pricing LANGUAGE the help carries ("COST:", "priced") is not a
# figure and is not matched.

money_re='(\$[0-9])|(\bUSD\b)|(\bEUR\b)|(\bGBP\b)|(€)|(£)'
for text in "$("$here/bin/behavior" --help 2>&1)" \
            "$("$here/bin/behavior" --harness fake --scenario probe-ok --arm green --plugin "$standin" --dry-run "${base[@]}" 2>&1)"; do
  if printf '%s\n' "$text" | grep -qE "$money_re"; then
    bad "the help and the dry run carry no monetary figure"
  else
    ok "the help and the dry run carry no monetary figure"
  fi
done

exit "$fails"
