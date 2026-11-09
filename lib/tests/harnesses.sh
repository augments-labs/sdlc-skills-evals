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

# The header's runnable flag, read the way the runners read it.
runnable_of() { grep '^runnable=' "$hh/$1.sh" | sed 's/^runnable=//'; }

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

# --- the README's provenance and evidence classes ----------------------------
# The Change paragraph asks the README to keep two evidence classes apart: a
# parser grounded in versioned official source or documentation may be
# exercised against a labelled synthetic fixture, and a synthetic fixture is
# never presented as an observation. So every parser's row names the source
# and its version, the fixture's provenance, and the runtime status.
readme="$hh/README.md"
if [ ! -f "$readme" ]; then
  bad "harnesses/README.md exists"
else
  ok "harnesses/README.md exists"
  # The two classes are named, and the rule that keeps them apart is stated.
  if grep -q '^\*\*Observed\.\*\*' "$readme" && \
     grep -q '^\*\*Documentation-grounded\.\*\*' "$readme" && \
     grep -qi 'never promotes' "$readme"; then
    ok "the README names both evidence classes and the rule that keeps them apart"
  else
    bad "the README names both evidence classes and the rule that keeps them apart"
  fi
  # The provenance table's row for one harness, tab-separated.
  provenance_row() { # $1 harness
    awk -v h="$1" '
      index($0, "| " h " |") == 1 {
        n = split($0, cell, "|")
        for (i = 2; i <= n - 1; i++) {
          gsub(/^[ \t]+|[ \t]+$/, "", cell[i])
          printf "%s%s", cell[i], (i < n - 1 ? "\t" : "\n")
        }
        exit
      }
    ' "$readme"
  }
  for h in "${adapters[@]}"; do
    row="$(provenance_row "$h")"
    if [ -z "$row" ]; then
      bad "$h has a provenance row (source and version, fixture provenance, runtime status)"
      continue
    fi
    shape="$(printf '%s\n' "$row" | cut -f3)"
    fixture="$(printf '%s\n' "$row" | cut -f4)"
    status="$(printf '%s\n' "$row" | cut -f5)"
    if [ -n "$shape" ] && printf '%s' "$shape" | grep -q '[0-9]'; then
      ok "$h provenance row names the source and its version"
    else
      bad "$h provenance row names the source and its version"
    fi
    # A synthetic fixture is labelled synthetic, never presented as an
    # observation.
    if printf '%s' "$fixture" | grep -qi 'synthetic'; then
      ok "$h provenance row labels its fixture synthetic"
    else
      bad "$h provenance row labels its fixture synthetic"
    fi
    if printf '%s' "$status" | grep -qiE 'observed|unverified'; then
      ok "$h provenance row states the runtime status"
    else
      bad "$h provenance row states the runtime status"
    fi
    # A flag is promoted by RECORDED evidence, not by a test's expectation:
    # a harness whose parser has never seen this CLI's own stream cannot be
    # called runnable. The one direction that holds is checked — runnable=yes
    # requires a provenance row that does not say unverified.
    if [ "$(runnable_of "$h")" = "yes" ] && printf '%s' "$status" | grep -qi 'unverified'; then
      bad "$h runnable=yes requires a provenance row that records an observed runtime status"
    else
      ok "$h runnable=yes requires a provenance row that records an observed runtime status"
    fi
  done
  # The procedure says what a run's evidence changes: the header's flag, the
  # provenance row's runtime status, and the value the contract test pins.
  procedure_section="$(awk '
    /^## The verification procedure/ { inside = 1 }
    /^## / && inside && $0 !~ /verification procedure/ { inside = 0 }
    inside { print }
  ' "$readme")"
  for want in 'runnable=yes' 'Runtime status' 'lib/tests/harnesses.sh'; do
    if printf '%s\n' "$procedure_section" | grep -qF -- "$want"; then
      ok "the procedure names what a run's evidence changes ($want)"
    else
      bad "the procedure names what a run's evidence changes ($want)"
    fi
  done
fi

# --- runnable values are honest -----------------------------------------------
# A flag the operator's own machine cannot support is `no`, with the reason
# that says what is missing. Only a harness with RECORDED evidence on this
# machine may say `yes`.
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
