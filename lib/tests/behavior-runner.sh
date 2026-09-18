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
trap 'rm -rf "$standin"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

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

exit "$fails"
