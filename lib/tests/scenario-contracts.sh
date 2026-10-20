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
# The ui-ux-design fixture leaves a preview startup record in /tmp, the way
# a real run's governed preview does. The test removes the ones it created.
trap 'rm -rf "$work"; rm -f /tmp/serve-preview.scenario-contracts-*.log' EXIT

SCEN_DIR="behavior/scenarios"
FIX_DIR="$here/lib/tests/fixtures/scenarios"
INV="config/upstream-inventory.json"

# The fixture helpers: the plan-version rule is compared with the pinned
# upstream script below, and the plan it compares is built by a fixture.
# shellcheck source=/dev/null
source "$here/fixtures/fixtures.sh"

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
    # The scenario does its own `cd "$d" || return 2`; this must not answer
    # for it, or the absent-workdir case would never reach the scenario.
    cd "$d" 2>/dev/null || true
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

# The pinned upstream tree, when this machine has one. The clause check and
# the plan-version check both read it; without it they SKIP, loudly, rather
# than pass silently.
PINNED=""
for cand in "${SDLC_SKILLS_ROOT:-}/skills" \
            "/tmp/opencode/sdlc-skills-pinned/skills"; do
  if [ -d "$cand" ]; then PINNED="$cand"; break; fi
done

# The locator an observed regression must carry: a specific record under the
# lab's record root. A file that merely exists is not evidence — `README.md`
# is not a stable locator for a failure.
evidence_locator_ok() { # $1 locator
  case "$1" in
    results/*) ;;
    *) return 1 ;;
  esac
  [ -e "$1" ]
}

for scen in "${scenarios[@]}"; do
  name="$(basename "$scen" .sh)"
  class="$(grep -cE '^# Provenance: (prospective contract probe|observed regression)$' "$scen")"
  if [ "$class" -ne 1 ]; then
    bad "$name declares exactly one provenance class (found $class)"
    continue
  fi
  if grep -qE '^# Provenance: prospective contract probe$' "$scen"; then
    clauses="$(grep -cE '^# Clause: skills/[a-z-]+/[a-z-]+/[A-Za-z0-9_.-]+ — ".+"$' "$scen" || true)"
    if [ "${clauses:-0}" -lt 1 ]; then
      bad "$name names the pinned skill clause it exercises"
      continue
    fi
    # EVERY clause line is checked, not only the first: a quote the pin does
    # not hold, a file that is not there, and a clause attributed to the wrong
    # file all have to be caught.
    clause_bad="" clause_n=0 clause_skipped=0
    while IFS= read -r clause; do
      [ -n "$clause" ] || continue
      clause_n=$((clause_n + 1))
      cfile="$(printf '%s' "$clause" | sed -n 's|^# Clause: \(skills/[^ ]*\) — .*|\1|p')"
      cquote="$(printf '%s' "$clause" | sed -n 's|^# Clause: skills/[^ ]* — \"\(.*\)"$|\1|p')"
      cskill="$(printf '%s' "$cfile" | cut -d/ -f2-3)"
      if ! skill_in_inventory "$cskill"; then
        clause_bad="$clause_bad $cfile(not-in-the-inventory)"
        continue
      fi
      if [ -z "$PINNED" ]; then
        clause_skipped=$((clause_skipped + 1))
        continue
      fi
      if [ ! -f "$PINNED/${cfile#skills/}" ]; then
        clause_bad="$clause_bad $cfile(no-such-file)"
        continue
      fi
      if ! grep -qF -- "$cquote" "$PINNED/${cfile#skills/}"; then
        clause_bad="$clause_bad $cfile(quote-not-in-that-file)"
      fi
    done < <(grep -E '^# Clause: ' "$scen" || true)
    if [ -n "$clause_bad" ]; then
      bad "$name quotes pinned clauses that hold:$clause_bad"
      continue
    fi
    if [ "$clause_skipped" -gt 0 ]; then
      printf '  SKIP  %s — no pinned upstream tree on this machine: %s clause quotes not checked\n' \
        "$name" "$clause_skipped"
    fi
    # A prospective probe cannot also claim observed-regression evidence.
    if grep -qE '^# Evidence: .+' "$scen"; then
      bad "$name is a prospective probe and claims no observed-regression evidence"
      continue
    fi
    ok "$name declares a prospective contract probe and every clause it quotes holds ($clause_n clauses)"
  else
    evidence="$(grep -m1 -E '^# Evidence: .+' "$scen" || true)"
    if [ -z "$evidence" ]; then
      bad "$name carries a stable evidence locator"
      continue
    fi
    locator="$(printf '%s' "$evidence" | sed 's|^# Evidence: ||')"
    if ! evidence_locator_ok "$locator"; then
      bad "$name carries a specific evidence locator under results/ ($locator)"
      continue
    fi
    ok "$name declares an observed regression with the locator $locator"
  fi
done

# The locator rule itself, probed: a file that merely exists is not a stable
# locator, and a record that does not exist is not evidence.
if evidence_locator_ok "README.md"; then
  bad "the evidence locator rule rejects a file that merely exists (README.md)"
else
  ok "the evidence locator rule rejects a file that merely exists (README.md)"
fi
if evidence_locator_ok "results/no-such-campaign/summary.md"; then
  bad "the evidence locator rule rejects a record that does not exist"
else
  ok "the evidence locator rule rejects a record that does not exist"
fi
if evidence_locator_ok "results/2026-09-18-sdd-opencode/summary.md"; then
  ok "the evidence locator rule accepts a specific record under results/"
else
  bad "the evidence locator rule accepts a specific record under results/"
fi

# --- 2. discrimination: a success artifact and a minimally wrong artifact ------
#
# The fixture convention is deliberately narrow, so that "minimally wrong"
# means what it says:
#
#   <name>/success/             the success artifact, a tree copied over the workdir
#   <name>/success.prepare.sh   optional; materializes what has to be computed
#                               (an identity, a revision) rather than written down
#   <name>/success-alt*.prepare.sh
#                               optional; a SECOND conformant artifact, for the
#                               cases where more than one answer is right
#   <name>/wrong*.prepare.sh    the mutation: one change to the success artifact
#                               that has to turn the scenario red
#
# The wrong artifact is therefore the success artifact plus ONE defect, and
# the mutation is the record of which check that defect turns.

# Copy the success tree into the workdir and rename the neutral `.sdlc-skills`
# root into the place the artifact really lives.
apply_success_tree() { # $1 name  $2 workdir
  local name="$1" d="$2" dir target
  [ -d "$FIX_DIR/$name/success" ] || return 0
  ( cd "$FIX_DIR/$name/success" && tar cf - . ) | ( cd "$d" && tar xf - )
  # The repository ignores every directory named `.sdlc-skills`, so the
  # fixture holds the artifact under a neutral name and the copy renames it
  # into the place the artifact really lives. A fixture placed under the
  # ignored name would be present in the working tree and absent from the
  # commit — the same failure the corpus's tracked root exists to end.
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    target="${dir%/_sdlc-skills}/.sdlc-skills"
    if [ -d "$target" ]; then
      ( cd "$dir" && tar cf - . ) | ( cd "$target" && tar xf - )
      rm -rf "$dir"
    else
      mv "$dir" "$target"
    fi
  done < <(find "$d" -type d -name '_sdlc-skills')
}

# Run a prepare script inside the workdir.
run_prepare() { # $1 script  $2 workdir  $3 stream file
  # shellcheck source=/dev/null
  ( cd "$2" && d="$2" && STREAM_FILE="$3" && export STREAM_FILE
    source "$here/fixtures/fixtures.sh"
    source "$1" ) >/dev/null 2>&1
}

# The files the success tree put in the workdir. A mutation that REMOVES one
# of them has not made the artifact wrong; it has made it absent, and the
# scenario then gives up instead of judging. Such a mutation is rejected.
success_tree_files() { # $1 name  $2 workdir
  local name="$1" d="$2"
  [ -d "$FIX_DIR/$name/success" ] || return 0
  ( cd "$FIX_DIR/$name/success" && find . -type f | sort ) | while IFS= read -r f; do
    [ -f "$d/$f" ] && printf '%s\n' "$f"
  done
}

# How many checks the success artifact ran, per scenario: a mutation has to be
# JUDGED, not merely noticed, so it has to run about as many checks.
declare -A succ_checks_of=()

for scen in "${scenarios[@]}"; do
  name="$(basename "$scen" .sh)"
  if [ ! -d "$FIX_DIR/$name/success" ] && [ ! -f "$FIX_DIR/$name/success.stream" ] \
     && [ ! -f "$FIX_DIR/$name/success.prepare.sh" ]; then
    bad "$name has a success artifact"
    continue
  fi
  if ! ls "$FIX_DIR/$name"/wrong*.prepare.sh >/dev/null 2>&1; then
    bad "$name has a minimally wrong artifact"
    continue
  fi

  # --- the conformant artifacts ------------------------------------------------
  for prepare in "$FIX_DIR/$name/success.prepare.sh" "$FIX_DIR/$name"/success-alt*.prepare.sh; do
    [ -f "$prepare" ] || continue
    label="$(basename "$prepare" .prepare.sh)"
    d="$work/$name-$label"
    if ! build_workdir "$scen" "$d"; then
      bad "$name $label — the fixture did not build"
      continue
    fi
    apply_success_tree "$name" "$d"
    stream_file="$work/$name-$label.stream"
    : > "$stream_file"
    [ -f "$FIX_DIR/$name/success.stream" ] && cp "$FIX_DIR/$name/success.stream" "$stream_file"
    if [ "$prepare" != "$FIX_DIR/$name/success.prepare.sh" ] && [ -f "$FIX_DIR/$name/success.prepare.sh" ]; then
      run_prepare "$FIX_DIR/$name/success.prepare.sh" "$d" "$stream_file"
    fi
    run_prepare "$prepare" "$d" "$stream_file"
    out="$(run_assert "$scen" "$d" "$stream_file")"
    rc=$?
    checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
    if [ "$rc" -eq 0 ]; then
      ok "$name accepts its $label artifact"
    else
      bad "$name accepts its $label artifact (exit $rc)"
      printf '%s\n' "$out" | sed 's/^/          /'
    fi
    if [ "${checks:-0}" -ge 1 ]; then
      ok "$name judged something in the $label case ($checks checks)"
    else
      bad "$name judged something in the $label case (no check ran)"
    fi
    [ "$label" = success ] && succ_checks_of[$name]="${checks:-0}"
  done

  # --- the mutations ------------------------------------------------------------
  for prepare in "$FIX_DIR/$name"/wrong*.prepare.sh; do
    [ -f "$prepare" ] || continue
    label="$(basename "$prepare" .prepare.sh)"
    d="$work/$name-$label"
    if ! build_workdir "$scen" "$d"; then
      bad "$name $label — the fixture did not build"
      continue
    fi
    apply_success_tree "$name" "$d"
    stream_file="$work/$name-$label.stream"
    : > "$stream_file"
    [ -f "$FIX_DIR/$name/success.stream" ] && cp "$FIX_DIR/$name/success.stream" "$stream_file"
    [ -f "$FIX_DIR/$name/success.prepare.sh" ] && run_prepare "$FIX_DIR/$name/success.prepare.sh" "$d" "$stream_file"
    present="$(success_tree_files "$name" "$d")"
    run_prepare "$prepare" "$d" "$stream_file"
    removed=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -e "$d/$f" ] || removed="$removed $f"
    done <<< "$present"
    if [ -n "$removed" ]; then
      bad "$name $label — the mutation removed the artifact instead of changing it:$removed"
      continue
    fi
    out="$(run_assert "$scen" "$d" "$stream_file")"
    rc=$?
    checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
    if [ "$rc" -eq 1 ]; then
      ok "$name rejects its $label artifact"
    elif [ "$rc" -eq 2 ]; then
      bad "$name rejects its $label artifact — the scenario called it inconclusive instead"
    else
      bad "$name rejects its $label artifact (exit $rc — it accepted it)"
      printf '%s\n' "$out" | sed 's/^/          /'
    fi
    succ_checks="${succ_checks_of[$name]:-0}"
    min_checks=$(( succ_checks / 2 ))
    if [ "${checks:-0}" -lt "$min_checks" ]; then
      bad "$name $label — the scenario gave up instead of judging ($checks checks against $succ_checks)"
    else
      ok "$name $label — the scenario judged and failed ($checks checks)"
    fi
  done
done

# --- 3. the indifferent: absent evidence is indeterminate, never a verdict -----
#
# Every scenario has to answer an absent-evidence case with INDETERMINATE, and
# with NO judgment run: `bin/behavior` composes a scenario that judged nothing
# into `indeterminate`, and a scenario that judged something into `fail`.
# Two cases are exercised for every scenario:
#
#   the workdir is gone       — the scenario cannot judge anything;
#   the tools are gone        — the verdict cannot be reached without them.
#
# The tools are the ones the scenario itself guards on, read out of its own
# `command -v` guards, so the list cannot drift from the code.

# A PATH from which the named tools cannot be found. The farm holds every
# executable the machine had, except the ones under test.
path_without() { # $1 space-separated tool list
  local key d dir f b
  key="$(printf '%s' "$1" | tr ' ' '_')"
  d="$work/path-no-$key"
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
    IFS=':' read -r -a _dirs <<< "$PATH"
    for dir in "${_dirs[@]}"; do
      [ -d "$dir" ] || continue
      for f in "$dir"/*; do
        b="${f##*/}"
        case " $1 " in *" $b "*) continue ;; esac
        [ -e "$d/$b" ] || ln -s "$f" "$d/$b" 2>/dev/null
      done
    done
  fi
  printf '%s' "$d"
}

for scen in "${scenarios[@]}"; do
  name="$(basename "$scen" .sh)"

  # (a) the workdir is gone.
  empty="$work/$name-empty.stream"
  : > "$empty"
  out="$(run_assert "$scen" "$work/$name-no-such-workdir" "$empty")"
  rc=$?
  checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
  if [ "$rc" -eq 2 ] && [ "${checks:-1}" -eq 0 ]; then
    ok "$name is inconclusive, and judges nothing, when its workdir is absent"
  else
    bad "$name is inconclusive when its workdir is absent (exit $rc, $checks checks)"
    printf '%s\n' "$out" | sed 's/^/          /'
  fi

  # (c) the event stream the scenario reads is gone.
  if grep -q '\${stream:-}' "$scen"; then
    d="$work/$name-no-stream"
    build_workdir "$scen" "$d" >/dev/null 2>&1 || { bad "$name — the fixture did not build"; continue; }
    apply_success_tree "$name" "$d"
    stream_file="$work/$name-no-stream.stream"
    : > "$stream_file"
    [ -f "$FIX_DIR/$name/success.prepare.sh" ] && run_prepare "$FIX_DIR/$name/success.prepare.sh" "$d" "$stream_file"
    out="$(run_assert "$scen" "$d" "$stream_file")"
    rc=$?
    checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
    if [ "$rc" -eq 2 ] && [ "${checks:-1}" -eq 0 ]; then
      ok "$name is inconclusive, and judges nothing, when its event stream is absent"
    else
      bad "$name is inconclusive when its event stream is absent (exit $rc, $checks checks)"
      printf '%s\n' "$out" | sed 's/^/          /'
    fi
  fi

  # (b) the tools the scenario guards on are gone.
  tools="$(grep -oE 'command -v [a-z0-9]+ >/dev/null' "$scen" | awk '{print $3}' | sort -u | tr '\n' ' ')"
  tools="${tools% }"
  if [ -z "$tools" ]; then
    printf '  SKIP  %s — no tool guard to remove\n' "$name"
    continue
  fi
  d="$work/$name-no-tools"
  build_workdir "$scen" "$d" >/dev/null 2>&1 || { bad "$name — the fixture did not build"; continue; }
  apply_success_tree "$name" "$d"
  stream_file="$work/$name-no-tools.stream"
  : > "$stream_file"
  [ -f "$FIX_DIR/$name/success.stream" ] && cp "$FIX_DIR/$name/success.stream" "$stream_file"
  [ -f "$FIX_DIR/$name/success.prepare.sh" ] && run_prepare "$FIX_DIR/$name/success.prepare.sh" "$d" "$stream_file"
  out="$(PATH="$(path_without "$tools")" run_assert "$scen" "$d" "$stream_file")"
  rc=$?
  checks="$(printf '%s\n' "$out" | sed -n 's/^CHECKS_RUN=//p' | tail -1)"
  if [ "$rc" -eq 2 ] && [ "${checks:-1}" -eq 0 ]; then
    ok "$name is inconclusive, and judges nothing, without $tools"
  else
    bad "$name is inconclusive without $tools (exit $rc, $checks checks)"
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
# The scratch the gate makes is a per-run DIRECTORY, so the check looks for
# whatever the gate leaves under the name, and compares before and after: an
# old entry from another run is not this run's leftover.
scratch_before="$(ls -d /tmp/check-manifest* 2>/dev/null | sort)"
( cd "$m5" && bash bin/check ) >/dev/null 2>&1
scratch_after="$(ls -d /tmp/check-manifest* 2>/dev/null | sort)"
scratch_new="$(comm -13 <(printf '%s\n' "$scratch_before") <(printf '%s\n' "$scratch_after") | tr '\n' ' ')"
if [ -n "$scratch_new" ]; then
  bad "a failed gate run leaves no scratch behind in /tmp (left: $scratch_new)"
  rm -rf $scratch_new
else
  ok "a failed gate run leaves no scratch behind in /tmp"
fi

# F-11: the plan version the scenarios compute must agree with the pinned
# upstream script. The lab's own rule is a re-implementation, and one that
# drifts is worse than none: the scenarios would exercise a version the
# upstream does not produce.
upstream_pv=""
for cand in "${SDLC_SKILLS_ROOT:-}/skills/design/writing-plans/scripts/plan-version.sh" \
            "$PINNED/design/writing-plans/scripts/plan-version.sh"; do
  if [ -f "$cand" ]; then upstream_pv="$cand"; break; fi
done
if [ -z "$upstream_pv" ]; then
  printf '  SKIP  the plan-version agreement — no pinned upstream tree on this machine\n'
else
  plan_root="$work/plan-version-check"
  mkdir -p "$plan_root"
  # shellcheck source=/dev/null
  ( source "$here/fixtures/fixtures.sh"; fixture_reviewable_plan "$plan_root" ) >/dev/null 2>&1
  plan_dir="$plan_root/.sdlc-skills/plans/2026-10-19-tenant-rollout"
  ours="$(fixture_plan_version "$plan_dir")"
  theirs="$(bash "$upstream_pv" "$plan_dir" 2>/dev/null || true)"
  if [ -z "$theirs" ]; then
    bad "the lab's plan version agrees with the pinned upstream script (the upstream script printed nothing)"
  elif [ "$ours" = "$theirs" ]; then
    ok "the lab's plan version agrees with the pinned upstream script ($ours)"
  else
    bad "the lab's plan version agrees with the pinned upstream script (ours $ours, upstream $theirs)"
  fi
fi

exit "$fails"
