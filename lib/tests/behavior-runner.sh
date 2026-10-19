#!/usr/bin/env bash
# Offline test: bin/behavior outcome classes via the fake harness only.
# Nothing here may launch a live CLI: every run uses --harness-dir
# lib/tests/fake-cli with --scenario-dir lib/tests/fake-cli/scenarios,
# except the two probes that exit before any launch. No token spent.
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
SDLC_SKILLS_ROOT="$standin" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green --plugin "$plug_commit" --record "$rec2" "${base[@]}" >/dev/null 2>&1
f2="$rec2/runs/probe-ok-green-1.json"
if [ -f "$f2" ]; then
  ok "a run pinned by commit is recorded"
  jq -e --arg c "$plug_commit" '.plugin_commit == $c and .verdict == "pass"' "$f2" >/dev/null \
    && ok "the record carries the pinned commit" || bad "the record carries the pinned commit"
else
  bad "a run pinned by commit is recorded"
fi
rm -rf "$rec2"

# the default pin is the committed one, and a run that cannot resolve it
# says so instead of running something else
out="$("$here/bin/behavior" --harness fake --scenario probe-ok --arm green \
  --dry-run "${base[@]}" 2>&1)"
printf '%s' "$out" | grep -qF "pin        : $inv_commit" \
  && ok "the default pin is the committed one" || bad "the default pin is the committed one"
SDLC_SKILLS_ROOT="$standin" "$here/bin/behavior" --harness fake --scenario probe-ok \
  --arm green "${base[@]}" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "a run that cannot resolve the default pin refuses" \
  || bad "a run that cannot resolve the default pin refuses"

exit "$fails"
