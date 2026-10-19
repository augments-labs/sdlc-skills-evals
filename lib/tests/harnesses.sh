#!/usr/bin/env bash
# Offline test: every harness launcher honors the live contract. No live run.
# Each launcher is sourced in its own subshell — all of them define the same
# adapter_* names, so one shell cannot hold more than one.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
hh="$here/harnesses"
INVENTORY="${INVENTORY_PATH:-$here/config/upstream-inventory.json}"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }
has_fn() { # $1 file $2 function — 0 iff defined after sourcing
  # $1 is a test input (our own launcher files), not a fixed path.
  # shellcheck disable=SC1090
  ( source "$1" >/dev/null 2>&1 && command -v "$2" >/dev/null 2>&1 )
}

required="adapter_check adapter_install adapter_chain adapter_run_activation adapter_run_behavioral"

# --- the adapter set is exactly the inventory's --------------------------------
# Exact equality with the 11-member inventory is mandatory: a launcher that
# is not in the inventory is an unowned adapter, and an inventory member
# without a launcher is an unsupported harness.
command -v jq >/dev/null 2>&1 || { echo "needs \`jq\`" >&2; exit 2; }
[ -f "$INVENTORY" ] || { echo "no upstream inventory at $INVENTORY" >&2; exit 2; }
mapfile -t adapters < <(jq -r '.harnesses[]' "$INVENTORY")
found="$(cd "$hh" && ls *.sh 2>/dev/null | sed 's/\.sh$//' | sort)"
want="$(printf '%s\n' "${adapters[@]}" | sort)"
if [ "$found" = "$want" ]; then
  ok "the adapter set equals the $(printf '%s\n' "${adapters[@]}" | wc -l | tr -d ' ')-member inventory"
else
  bad "the adapter set equals the inventory (have: $(printf '%s' "$found" | tr '\n' ' '))"
fi

for h in "${adapters[@]}"; do
  name="$h.sh"
  [ -f "$hh/$name" ] || { bad "$name exists"; continue; }
  for fn in $required; do
    if has_fn "$hh/$name" "$fn"; then ok "$name defines $fn";
    else bad "$name defines $fn"; fi
  done
  for field in runnable runnable_reason permission_flags capabilities; do
    if grep -q "^$field=" "$hh/$name"; then ok "$name header carries $field";
    else bad "$name header carries $field"; fi
  done
  # the header must not claim flags the file never passes (the header
  # line itself is excluded, so a bare claim cannot satisfy this)
  flags="$(grep '^permission_flags=' "$hh/$name" | sed 's/^permission_flags=//; s/^"//; s/"$//')"
  if [ -n "$flags" ]; then
    if grep -v '^permission_flags=' "$hh/$name" | grep -qF -- "$flags"; then ok "$name permission_flags matches a passed flag";
    else bad "$name permission_flags matches a passed flag ($flags)"; fi
  else
    bad "$name permission_flags is non-empty"
  fi
  # an adapter that claims to be runnable must say WHY, and an adapter that
  # is not runnable must name the missing evidence
  reason="$(grep '^runnable_reason=' "$hh/$name" | sed 's/^runnable_reason=//; s/^"//; s/"$//')"
  if [ -n "$reason" ]; then ok "$name states a runnable_reason";
  else bad "$name states a runnable_reason"; fi
  # every capability claim carries its evidence class, in the documented
  # form: the claim first, the evidence class in the parentheses — e.g.
  # `subagent-loads-skills=yes(documentation)`. A claim without its
  # evidence class cannot be weighed by whoever reads the header, so the
  # shape is checked rather than trusted, and each of the five documented
  # capabilities is required to be there.
  caps="$(grep '^capabilities=' "$hh/$name" | sed 's/^capabilities=//; s/^"//; s/"$//')"
  bad_caps="$(printf '%s\n' "$caps" | tr ' ' '\n' \
    | grep -vcE '^[a-z-]+=[a-z]+\((run|documentation)\)$' 2>/dev/null || true)"
  total_caps="$(printf '%s\n' "$caps" | tr ' ' '\n' | grep -c '=' 2>/dev/null || true)"
  missing=""
  for want in subagent-loads-skills nesting-depth tier-settable \
              session-start-event post-compaction-event; do
    printf '%s\n' "$caps" | tr ' ' '\n' | grep -q "^$want=" || missing="$missing $want"
  done
  if [ "$total_caps" -gt 0 ] && [ "$bad_caps" -eq 0 ] && [ -z "$missing" ]; then
    ok "$name capabilities carry their evidence class"
  else
    bad "$name capabilities carry their evidence class (malformed:$bad_caps missing:$missing )"
  fi
  # an adapter reaches its CLI by NAME, through PATH. A literal path to a
  # home or a system directory would reach the operator's real CLI whatever
  # the caller's PATH says, so it is refused here: every path an adapter
  # names is a variable expansion.
  literal="$(grep -nE '(^|[^$[:alnum:]_./-])/(home|Users|root|opt|srv|var|Applications)(/|[^[:alnum:]_.-]|$)' \
    "$hh/$name" | head -3)"
  if [ -z "$literal" ]; then
    ok "$name names no literal path to a CLI installation"
  else
    bad "$name names no literal path to a CLI installation: $literal"
  fi
done

# --- runnable values are honest -----------------------------------------------
# A flag the operator's own machine cannot support is `no`, with the reason
# that says what is missing. Only a harness with RECORDED evidence on this
# machine may say `yes`.
runnable_of() { grep '^runnable=' "$hh/$1.sh" | sed 's/^runnable=//'; }
expect_runnable() { # $1 harness $2 yes|no
  if [ "$(runnable_of "$1")" = "$2" ]; then
    ok "$1 runnable=$2"
  else
    bad "$1 runnable=$2 (got $(runnable_of "$1"))"
  fi
}
expect_runnable opencode yes
expect_runnable claude-code yes
expect_runnable codex no
expect_runnable kimi-code no
expect_runnable antigravity no
expect_runnable cursor no
expect_runnable devin no
expect_runnable grok no
expect_runnable hermes no
expect_runnable muse no
expect_runnable pi no

exit "$fails"
