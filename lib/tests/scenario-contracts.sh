#!/usr/bin/env bash
# Offline test: the behaviour scenarios' contracts.
#
# Three things are checked here, and none of them runs an agent:
#
#   1. PROVENANCE. Every scenario declares one of the two classes the plan
#      allows: an observed regression with a stable evidence locator, or a
#      prospective contract probe that names the pinned skill clause it
#      exercises. A prospective probe that also claims observed-regression
#      evidence is rejected: the lab holds no record it could point at.
#   2. DISCRIMINATION. Every scenario has a success artifact and a minimally
#      wrong artifact under lib/tests/fixtures/scenarios/, and the scenario's
#      OWN scenario_assert — unchanged — accepts the first and rejects the
#      second. A check that cannot tell the two apart is decoration, and this
#      is what proves it is not.
#   3. THE INDIFFERENT. A scenario whose evidence is absent (no event
#      stream) is inconclusive, never green and never red; a scenario whose
#      assertions judge nothing is not a pass either.
#
# The frozen manifests and the suite membership are checked here too: they
# belong to this task, and a stale manifest or a suite that disagrees with
# the manifests has to turn the gate red.
#
# Nothing here launches a CLI, a model, or a network call. The scenarios are
# sourced and their assertions are run against artifacts built in a
# throwaway directory.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here" || exit 1

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

SCEN_DIR="behavior/scenarios"
FIX_DIR="$here/lib/tests/fixtures/scenarios"
INV="config/upstream-inventory.json"

# --- the harness the scenarios expect ----------------------------------------

# The scenarios read the harness's own bindings. The offline test supplies
# the same bindings the claude-code adapter exposes, over the same stream
# shape, so a scenario that reads them offline reads them the same way a
# live run does.
adapter_chain() { # $1 stream file
  jq -r 'select(.type=="assistant") | .message.content[]?
         | select(.type=="tool_use" and .name=="Skill") | .input.skill' "$1" 2>/dev/null
}
adapter_behavioral_events() { # $1 stream file
  jq -r 'select(.type=="assistant") | .message.content[]?
         | select(.type=="tool_use")
         | if .name=="Skill" then "SKILL " + (.input.skill // "")
           elif (.name=="Write" or .name=="Edit" or .name=="MultiEdit")
           then "EDIT " + (.input.file_path // .input.path // "")
           else empty end' "$1" 2>/dev/null
}
export -f adapter_chain adapter_behavioral_events

# --- helpers ------------------------------------------------------------------

# The workdir a scenario is judged in: the fixture, then the runner's own
# baseline commit and task branch, exactly as bin/behavior builds them.
build_workdir() { # $1 scenario file  $2 workdir
  local scen="$1" d="$2" branch
  rm -rf "$d"; mkdir -p "$d"
  (
    set -uo pipefail
    # shellcheck source=/dev/null
    source "$here/lib/prelude.sh"
    # shellcheck source=/dev/null
    source "$here/fixtures/fixtures.sh"
    # shellcheck source=/dev/null
    source "$scen"
    scenario_setup "$d"
  ) >/dev/null 2>&1
  # A scenario may name the branch the runner puts the workdir on.
  branch="$(grep -m1 -E '^scenario_branch=' "$scen" | sed 's/^scenario_branch=//' | tr -d "\"' " || true)"
  branch="${branch:-task/behavioral-probe}"
  (
    cd "$d" || exit 1
    git init -q . 2>/dev/null || exit 1
    git add -A
    git -c user.name='sdlc-skills-evals' -c user.email='evals@example.invalid' \
        commit -q -m 'scenario baseline' >/dev/null 2>&1
    git switch -qc "$branch" >/dev/null 2>&1
  ) || return 1
  return 0
}

# Run the scenario's own assertion over a prepared workdir. Prints the
# assertion's raw output, then the verdict: the exit code, and how many
# judgments ran.
run_assert() { # $1 scenario file  $2 workdir  $3 stream file
  local scen="$1" d="$2" stream_file="$3"
  (
    set -uo pipefail
    # shellcheck source=/dev/null
    source "$here/lib/prelude.sh"
    # shellcheck source=/dev/null
    source "$here/fixtures/fixtures.sh"
    # shellcheck source=/dev/null
    source "$scen"
    cd "$d" || exit 2
    stream="$stream_file"
    export stream
    scenario_assert "$d"
    rc=$?
    # The counter is the prelude's; it is assigned there, not here.
    # shellcheck disable=SC2154
    printf 'CHECKS_RUN=%s\n' "$_lab_checks_run"
    exit "$rc"
  ) 2>&1
}

# --- 1. provenance ------------------------------------------------------------

mapfile -t scenarios < <(find "$SCEN_DIR" -maxdepth 1 -name '*.sh' -type f | sort)
mapfile -t inventory < <(jq -r '.skills[]' "$INV")

skill_in_inventory() { # $1 skill, e.g. analysis/working-from-a-ticket
  local s
  for s in "${inventory[@]}"; do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

for scen in "${scenarios[@]}"; do
  name="$(basename "$scen" .sh)"
  class="$(grep -cE '^# Provenance: (prospective contract probe|observed regression)$' "$scen")"
  if [ "$class" -ne 1 ]; then
    bad "$name declares exactly one provenance class (found $class)"
    continue
  fi
  if grep -qE '^# Provenance: prospective contract probe$' "$scen"; then
    clause="$(grep -m1 -E '^# Clause: skills/[a-z-]+/[a-z-]+/SKILL\.md — ".+"$' "$scen" || true)"
    if [ -z "$clause" ]; then
      bad "$name names the pinned skill clause it exercises"
      continue
    fi
    skill="$(printf '%s' "$clause" | sed -n 's|^# Clause: skills/\([a-z-]*/[a-z-]*\)/SKILL\.md — .*|\1|p')"
    if ! skill_in_inventory "$skill"; then
      bad "$name names a skill in the pinned inventory ($skill)"
      continue
    fi
    # A prospective probe cannot also claim observed-regression evidence.
    if grep -qE '^# Evidence: .+' "$scen"; then
      bad "$name is a prospective probe and claims no observed-regression evidence"
      continue
    fi
    ok "$name declares a prospective contract probe on $skill"
  else
    evidence="$(grep -m1 -E '^# Evidence: .+' "$scen" || true)"
    if [ -z "$evidence" ]; then
      bad "$name carries a stable evidence locator"
      continue
    fi
    locator="$(printf '%s' "$evidence" | sed 's|^# Evidence: ||')"
    if [ ! -e "$locator" ]; then
      bad "$name carries a stable evidence locator that exists ($locator)"
      continue
    fi
    ok "$name declares an observed regression with the locator $locator"
  fi
done

# --- 2. discrimination: a success artifact and a minimally wrong artifact ------
#
# The fixture convention is deliberately narrow, so that "minimally wrong"
# means what it says:
#
#   <name>/success/            the success artifact, a tree copied over the workdir
#   <name>/success.prepare.sh  optional; materializes what has to be computed
#                              (an identity, a revision) rather than written down
#   <name>/wrong.prepare.sh    the mutation: one change to the success artifact
#                              that has to turn the scenario red
#
# The wrong artifact is therefore the success artifact plus ONE defect, and
# the mutation is the record of which check that defect turns.

for scen in "${scenarios[@]}"; do
  name="$(basename "$scen" .sh)"
  if [ ! -d "$FIX_DIR/$name/success" ] && [ ! -f "$FIX_DIR/$name/success.stream" ] \
     && [ ! -f "$FIX_DIR/$name/success.prepare.sh" ]; then
    bad "$name has a success artifact"
    continue
  fi
  if [ ! -f "$FIX_DIR/$name/wrong.prepare.sh" ]; then
    bad "$name has a minimally wrong artifact"
    continue
  fi
  for case_name in success wrong; do
    d="$work/$name-$case_name"
    if ! build_workdir "$scen" "$d"; then
      bad "$name $case_name — the fixture did not build"
      continue
    fi
    if [ -d "$FIX_DIR/$name/success" ]; then
      ( cd "$FIX_DIR/$name/success" && tar cf - . ) | ( cd "$d" && tar xf - )
    fi
    stream_file="$work/$name-$case_name.stream"
    : > "$stream_file"
    if [ -f "$FIX_DIR/$name/success.stream" ]; then
      cp "$FIX_DIR/$name/success.stream" "$stream_file"
    fi
    if [ -f "$FIX_DIR/$name/success.prepare.sh" ]; then
      # The prepare script runs INSIDE the workdir: its paths are the paths
      # the scenario will read.
      # shellcheck source=/dev/null
      ( cd "$d" && d="$d" && STREAM_FILE="$stream_file" && export STREAM_FILE
        source "$here/fixtures/fixtures.sh"
        source "$FIX_DIR/$name/success.prepare.sh" ) >/dev/null 2>&1
    fi
    if [ "$case_name" = wrong ]; then
      # shellcheck source=/dev/null
      ( cd "$d" && d="$d" && STREAM_FILE="$stream_file" && export STREAM_FILE
        source "$here/fixtures/fixtures.sh"
        source "$FIX_DIR/$name/wrong.prepare.sh" ) >/dev/null 2>&1
    fi
    out="$(run_assert "$scen" "$d" "$stream_file")"
    rc=$?
    checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
    case "$case_name" in
      success)
        if [ "$rc" -eq 0 ]; then
          ok "$name accepts its success artifact"
        else
          bad "$name accepts its success artifact (exit $rc)"
          printf '%s\n' "$out" | sed 's/^/          /'
        fi
        if [ "${checks:-0}" -ge 1 ]; then
          ok "$name judged something in the success case ($checks checks)"
        else
          bad "$name judged something in the success case (no check ran)"
        fi
        ;;
      wrong)
        if [ "$rc" -eq 1 ]; then
          ok "$name rejects its minimally wrong artifact"
        elif [ "$rc" -eq 2 ]; then
          bad "$name rejects its minimally wrong artifact — the scenario called it inconclusive instead"
        else
          bad "$name rejects its minimally wrong artifact (exit $rc — it accepted it)"
          printf '%s\n' "$out" | sed 's/^/          /'
        fi
        ;;
    esac
  done
done

# --- 3. the indifferent: absent evidence is inconclusive, never a verdict -----

# The scenarios whose verdict rests on the event stream. With the stream
# absent they must be inconclusive, never green and never red: an absent
# record is not a defect and not a pass.
#
# The two scenarios that read the stream as well are not in this list,
# because their verdict rests on artifacts the stream only decorates:
# `hollow-floor-routing` judges whether the project's floor bites, and
# `using-git-worktrees` judges the worktree and the untouched checkout.
stream_judged=(
  done-boundary-routing
  implementation-entry-routing
  pending-decision-authority
  plan-execution-entry
  subagent-driven-development
)
for name in "${stream_judged[@]}"; do
  scen="$SCEN_DIR/$name.sh"
  [ -f "$scen" ] || { bad "$name exists to be judged on its stream"; continue; }
  d="$work/$name-absent"
  build_workdir "$scen" "$d" >/dev/null 2>&1 || { bad "$name — the fixture did not build"; continue; }
  empty="$work/$name-empty.stream"
  : > "$empty"
  out="$(run_assert "$scen" "$d" "$empty")"
  rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "$name is inconclusive when its evidence is absent"
  else
    bad "$name is inconclusive when its evidence is absent (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/          /'
  fi
done

# --- 4. the frozen manifests and the suite membership -------------------------

check_rc=0
check_out=""
run_gate() { # $1 root
  local root="$1"
  ( cd "$root" && bash bin/check ) >"$work/gate.out" 2>&1
  check_rc=$?
  check_out="$(cat "$work/gate.out")"
}
expect_fail() { # $1 label, $2 the message the failure must carry
  if [ "$check_rc" -eq 0 ]; then
    bad "$1 (the gate accepted it)"
  elif printf '%s\n' "$check_out" | grep -qF "$2"; then
    ok "$1"
  else
    bad "$1 (exit $check_rc, no '$2' in: $(printf '%s\n' "$check_out" | tail -3 | tr '\n' ' '))"
  fi
}
expect_pass() { # $1 label
  if [ "$check_rc" -eq 0 ]; then
    ok "$1"
  else
    bad "$1 (exit $check_rc): $(printf '%s\n' "$check_out" | tail -3 | tr '\n' ' ')"
  fi
}

copy_repo() { # $1 destination
  mkdir -p "$1"
  ( cd "$here" && tar --exclude=.git --exclude=workspaces -cf - . ) | ( cd "$1" && tar xf - )
}

m1="$work/m1"; copy_repo "$m1"
run_gate "$m1"
expect_pass "the committed scenarios and manifests pass the gate"

# A stale manifest: the scenario changed, the frozen manifest did not.
m2="$work/m2"; copy_repo "$m2"
printf '\n# a check verb the frozen manifest does not carry\nassert_contains "x" "x" "extra" >/dev/null\n' >> "$m2/$SCEN_DIR/debugging.sh"
run_gate "$m2"
expect_fail "a stale frozen manifest is rejected" "stale manifest for debugging"

# A suite whose membership disagrees with the manifests: a scenario that is
# not listed in the suite the gate holds the membership of.
m3="$work/m3"; copy_repo "$m3"
grep -v '^debugging$' "$m3/behavior/suites/all.txt" > "$m3/behavior/suites/all.txt.new"
mv "$m3/behavior/suites/all.txt.new" "$m3/behavior/suites/all.txt"
run_gate "$m3"
expect_fail "a scenario missing from the suite is rejected" "not listed in behavior/suites/all.txt"

# A routing suite row that names a scenario the suite does not hold.
m4="$work/m4"; copy_repo "$m4"
printf 'no-such-scenario\n' >> "$m4/behavior/suites/routing.txt"
run_gate "$m4"
expect_fail "a routing row that names no listed scenario is rejected" "routing scenario not in suite"

# The gate leaves no scratch file behind, and two concurrent runs in two
# trees cannot read each other's bytes.
m5="$work/m5"; copy_repo "$m5"
printf '\n# a check verb the frozen manifest does not carry\nassert_contains "x" "x" "extra" >/dev/null\n' >> "$m5/$SCEN_DIR/debugging.sh"
rm -f /tmp/check-manifest-*.json
( cd "$m5" && bash bin/check ) >/dev/null 2>&1
if ls /tmp/check-manifest-*.json >/dev/null 2>&1; then
  bad "a failed gate run leaves no scratch file behind in /tmp"
  rm -f /tmp/check-manifest-*.json
else
  ok "a failed gate run leaves no scratch file behind in /tmp"
fi

exit "$fails"
