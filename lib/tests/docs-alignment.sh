#!/usr/bin/env bash
# Offline test: the lab's active documentation describes the lab that exists.
# It checks the pin every doc cites against config/upstream-inventory.json,
# the two agentskills.io workflows (bin/evaluate -> bin/grade -> bin/benchmark
# -> bin/report, and bin/triggering -> bin/optimize-description), the
# user-run-only rule in CLAUDE.md, the README's `## Running it yourself`
# runbook (every flag it shows is one its tool's --help names, and every
# live command comes after its own --dry-run form), and that no active doc
# still instructs the retired bash-scenario lab. Each detector is pinned
# first against an input it must flag and a near-miss it must pass.
#
# docs/upstream-coverage.md is a provenance record: only its `## The pin`,
# documented-pin-rows, `<!-- corpus-state -->` and `## The corpus audit`
# sections are checked, so its historical E-0..E-14 rows stay as written.
# No live run: every tool is asked for --help only.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$here" || exit 1

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }
check() { # $1 description; the rest is the command that must succeed
  local what="$1"; shift
  if "$@"; then ok "$what"; else bad "$what"; fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The active documentation: every guide a contributor or operator follows.
active_docs=(CLAUDE.md README.md SECURITY.md descriptions/README.md
  descriptions/holdout/README.md evals/README.md docs/authoring.md
  docs/triage.md docs/adding-a-harness.md results/README.md lib/README.md
  fixtures/README.md harnesses/README.md .github/PULL_REQUEST_TEMPLATE.md)

# Instructions for the retired lab: its runners, scenario files, assertion
# library, manifests, and the phase-nested corpus layout.
stale_re='v10\.2\.1|bin/behavior|bin/campaign|behavior/(scenarios|suites|evals|checks-manifest)|prelude\.sh|verdict\.sh|<phase>/<skill>|--update-manifests|scenario_(opening|setup|assert)'

# The launchers that spend the user's quota when run without --dry-run.
live_tools='evaluate|optimize-description|triggering'

# --- the detectors ----------------------------------------------------------

stale_lines() { # $@ files — every line that instructs the retired lab
  grep -nHE -- "$stale_re" "$@" 2>/dev/null
}

runbook() { # $1 markdown file — the `## Running it yourself` section
  awk '/^## Running it yourself[[:space:]]*$/ { f = 1; next } f && /^## / { exit } f' "$1"
}

commands_of() { # stdin markdown — each bin/ command in a fenced block, one per line
  awk '
    /^[[:space:]]*```/ { inblock = !inblock; next }
    !inblock { next }
    { sub(/^[[:space:]]+/, "") }
    cont { line = line " " $0 } !cont { line = $0 }
    /\\$/ { sub(/[[:space:]]*\\$/, "", line); cont = 1; next }
    { cont = 0; if (line ~ /^bin\//) print line }
  ' | tr -s ' '
}

unknown_flags() { # stdin command lines — "tool --flag" for each flag --help does not name
  local line tool tok help
  while IFS= read -r line; do
    tool="${line%% *}"
    if [ ! -x "$tool" ] || [ "$tool" = bin/check ]; then
      printf '%s (no --help to check against)\n' "$tool"; continue
    fi
    help="$(bash "$tool" --help </dev/null 2>&1)"
    for tok in $line; do
      case "$tok" in --*) ;; *) continue;; esac
      tok="${tok%%=*}"
      grep -qE -- "(^|[^[:alnum:]-])${tok}([^[:alnum:]-]|\$)" <<<"$help" \
        || printf '%s %s\n' "$tool" "$tok"
    done
  done
}

broken_links() { # $1 root, $2.. files — "file: target" for each relative link that leaves the root or names nothing
  local root="$1" f t r; shift
  for f in "$@"; do
    while IFS= read -r t; do
      case "$t" in ''|http://*|https://*|mailto:*) continue;; esac
      r="$(realpath -m "$(dirname "$f")/$t")"
      [[ "$r" == "$root"/* ]] && [ -e "$r" ] || printf '%s: %s\n' "$f" "$t"
    done < <(grep -oE '\]\([^)#[:space:]]+' "$f" | sed 's/^](//')
  done
}

normalized() { # $1 command line — its words sorted, --dry-run removed
  tr ' ' '\n' <<<"$1" | grep -vx -- '--dry-run' | sort | tr '\n' ' '
}

unpriced_live() { # stdin command lines — each live command with no earlier --dry-run form
  local line seen=() s found tool
  while IFS= read -r line; do
    tool="${line%% *}"; found=0
    if [[ "$tool" =~ ^bin/($live_tools)$ ]] && [[ " $line " != *" --dry-run "* ]]; then
      for s in "${seen[@]+"${seen[@]}"}"; do
        [[ " $s " == *" --dry-run "* ]] && [ "${s%% *}" = "$tool" ] \
          && [ "$(normalized "$s")" = "$(normalized "$line")" ] && found=1
      done
      [ "$found" = 1 ] || printf '%s\n' "$line"
    elif [ "$tool" = bin/grade ] && [[ " $line " == *" --harness "* ]]; then
      # bin/grade has no dry run: the rubric grader is priced by
      # bin/evaluate --dry-run --grade-with-harness
      for s in "${seen[@]+"${seen[@]}"}"; do
        [[ "$s" == bin/evaluate* && " $s " == *" --dry-run "* && " $s " == *" --grade-with-harness "* ]] && found=1
      done
      [ "$found" = 1 ] || printf '%s\n' "$line"
    fi
    seen+=("$line")
  done
}

# --- each detector against an input it must flag and a near-miss ------------

printf 'run bin/behavior --scenario x\n' >"$work/stale.md"
printf 'run bin/benchmark on adapter_run_behavioral output, pinned at v12.0.0\n' >"$work/near.md"
[ -n "$(stale_lines "$work/stale.md")" ] && [ -z "$(stale_lines "$work/near.md")" ] \
  && ok "the stale-instruction detector flags bin/behavior and passes bin/benchmark" \
  || bad "the stale-instruction detector flags bin/behavior and passes bin/benchmark"

[ "$(printf '```bash\nbin/evaluate --harness opencode \\\n  --skill yagni --bogus\n```\n' | commands_of | unknown_flags)" = "bin/evaluate --bogus" ] \
  && [ -z "$(printf '```bash\nbin/evaluate --harness opencode --skill yagni --dry-run\n```\n' | commands_of | unknown_flags)" ] \
  && ok "the flag detector flags a flag --help does not name and passes one it does" \
  || bad "the flag detector flags a flag --help does not name and passes one it does"

[ -n "$(printf 'bin/triggering --harness opencode --skill yagni --dry-run\nbin/triggering --harness opencode --skill yagni --split train\n' | unpriced_live)" ] \
  && [ -z "$(printf 'bin/triggering --harness opencode --skill yagni --split train --dry-run\nbin/triggering --harness opencode --skill yagni --split train\n' | unpriced_live)" ] \
  && [ -n "$(printf 'bin/evaluate --harness opencode --skill yagni --dry-run\nbin/grade d --harness opencode\n' | unpriced_live)" ] \
  && [ -z "$(printf 'bin/evaluate --harness opencode --skill yagni --grade-with-harness --dry-run\nbin/grade d --harness opencode\n' | unpriced_live)" ] \
  && ok "the pricing detector flags a live command whose own --dry-run form did not come first" \
  || bad "the pricing detector flags a live command whose own --dry-run form did not come first"

mkdir -p "$work/repo"; : >"$work/repo/real.md"
printf 'see [the plugin](../sdlc-skills) and [x](real.md)\n' >"$work/repo/out.md"
printf 'see [the plugin](https://github.com/augments-labs/sdlc-skills), [x](real.md), [y](#top)\n' >"$work/repo/in.md"
[ "$(broken_links "$work/repo" "$work/repo/out.md")" = "$work/repo/out.md: ../sdlc-skills" ] \
  && [ -z "$(broken_links "$work/repo" "$work/repo/in.md")" ] \
  && ok "the link detector flags a relative link out of the repo and passes a URL, an in-repo path, and an anchor" \
  || bad "the link detector flags a relative link out of the repo and passes a URL, an in-repo path, and an anchor"

# --- the files exist, and AGENTS.md is CLAUDE.md ----------------------------

missing=""
for f in "${active_docs[@]}" docs/upstream-coverage.md; do [ -f "$f" ] || missing="$missing $f"; done
[ -z "$missing" ] && ok "all ${#active_docs[@]} active docs and the coverage record exist" \
  || bad "all active docs and the coverage record exist (missing:$missing)"
check "AGENTS.md is a symlink to CLAUDE.md" test -L AGENTS.md -a "$(readlink AGENTS.md 2>/dev/null)" = CLAUDE.md

# --- no active doc instructs the retired lab --------------------------------

stale="$(stale_lines "${active_docs[@]}")"
[ -z "$stale" ] && ok "no active doc names v10.2.1, a retired runner, scenario, or the <phase>/<skill> layout" \
  || { bad "no active doc names v10.2.1, a retired runner, scenario, or the <phase>/<skill> layout ($(grep -c . <<<"$stale") line(s))"
       head -12 <<<"$stale" | sed 's/^/        /'; }
ban="$(grep -nHiE 'runs nowhere|no selection run ever starts|never run a triggering selection loop' "${active_docs[@]}" 2>/dev/null)"
[ -z "$ban" ] && ok "no active doc keeps the lifted ban on a user-run optimization loop" \
  || bad "no active doc keeps the lifted ban on a user-run optimization loop ($(head -3 <<<"$ban" | tr '\n' ' '))"

links="$(broken_links "$here" "${active_docs[@]}")"
[ -z "$links" ] && ok "every relative link in the active docs resolves inside the repository" \
  || bad "every relative link in the active docs resolves inside the repository ($(head -3 <<<"$links" | tr '\n' ';'))"

# --- the pin -----------------------------------------------------------------

pin="$(jq -r '.upstream.commit' config/upstream-inventory.json)"
ver="$(jq -r '.upstream.version' config/upstream-inventory.json)"
check "the inventory pins commit c1e995a0371b11271b1d9a393e89fb2f345b2611 (12.0.0)" \
  test "$pin $ver" = "c1e995a0371b11271b1d9a393e89fb2f345b2611 12.0.0"
for f in README.md .github/PULL_REQUEST_TEMPLATE.md; do
  check "$f names the pinned commit $pin" grep -qF -- "$pin" "$f"
done
pin_section="$(awk '/^## The pin[[:space:]]*$/ { f = 1; next } f && /^## / { exit } f' docs/upstream-coverage.md)"
grep -qF -- "| Commit | \`$pin\`" <<<"$pin_section" && grep -qF -- "| Package version | \`$ver\`" <<<"$pin_section" \
  && ok "docs/upstream-coverage.md ## The pin names $pin and $ver" \
  || bad "docs/upstream-coverage.md ## The pin names $pin and $ver"
rows_heading="$(grep -E '^### Documented pin rows that still name the v10\.2\.1 tag \([0-9]+\)$' docs/upstream-coverage.md)"
rows_body="$(awk '/^### Documented pin rows that still name the v10\.2\.1 tag/ { f = 1; next } f && /^#/ { exit } f' docs/upstream-coverage.md)"
[ "$rows_heading" = "### Documented pin rows that still name the v10.2.1 tag (0)" ] \
  && [ "$(grep -v '^[[:space:]]*$' <<<"$rows_body")" = "None." ] \
  && ok "the coverage record's documented-pin-rows section is (0) / None." \
  || bad "the coverage record's documented-pin-rows section is (0) / None. (heading: ${rows_heading:-absent})"
sed -n '/^<!-- corpus-state:begin -->$/,/^<!-- corpus-state:end -->$/p' docs/upstream-coverage.md \
  | sed '1,2d;$d' | sed '$d' | jq -e '.frozen_splits | type == "object"' >/dev/null 2>&1 \
  && grep -q '^## The corpus audit' docs/upstream-coverage.md \
  && ok "the corpus-state block parses and the corpus audit section stands" \
  || bad "the corpus-state block parses and the corpus audit section stands"

# --- CLAUDE.md: user-run-only, offline build and CI, flat authoring -----------

check "CLAUDE.md states the user-run-only rule" grep -qi 'user-run-only' CLAUDE.md
check "CLAUDE.md grants no live run on a recorded go" bash -c '! grep -qi "recorded go" CLAUDE.md'
named=""
for t in 'bin/evaluate' 'bin/optimize-description' 'bin/triggering' 'bin/grade --harness' '--dry-run'; do
  grep -qF -- "$t" CLAUDE.md || named="$named $t"
done
for c in lib/tests/tripwire/*; do
  grep -qF -- "\`$(basename "$c")\`" CLAUDE.md || named="$named $(basename "$c")"
done
[ -z "$named" ] && ok "CLAUDE.md names every live launcher, --dry-run, and every agent CLI the tripwire guards" \
  || bad "CLAUDE.md names every live launcher, --dry-run, and every agent CLI the tripwire guards (missing:$named)"
for t in 'evals/<skill>/evals.json' 'descriptions/<skill>.json' 'tripwire'; do
  check "CLAUDE.md names $t" grep -qF -- "$t" CLAUDE.md
done

# --- the two workflows are documented ----------------------------------------

for f in CLAUDE.md README.md; do
  gaps=""
  for t in bin/evaluate bin/grade bin/benchmark bin/report bin/triggering bin/optimize-description; do
    grep -qF -- "$t" "$f" || gaps="$gaps $t"
  done
  [ -z "$gaps" ] && ok "$f names both workflows' tools" || bad "$f names both workflows' tools (missing:$gaps)"
done
for t in bin/evaluate bin/optimize-description; do
  check "SECURITY.md names $t" grep -qF -- "$t" SECURITY.md
done

# --- README.md ## Running it yourself ---------------------------------------

runbook README.md >"$work/runbook.md"
if [ ! -s "$work/runbook.md" ]; then
  bad "README.md has a ## Running it yourself section"
else
  ok "README.md has a ## Running it yourself section"
  commands_of <"$work/runbook.md" >"$work/commands"
  tools_shown="$(cut -d' ' -f1 "$work/commands" | sort -u | tr '\n' ' ')"
  gaps=""
  for t in bin/evaluate bin/grade bin/benchmark bin/report bin/triggering bin/optimize-description; do
    [[ " $tools_shown " == *" $t "* ]] || gaps="$gaps $t"
  done
  [ -z "$gaps" ] && ok "the runbook shows a command for every tool of both workflows" \
    || bad "the runbook shows a command for every tool of both workflows (missing:$gaps)"
  unknown="$(unknown_flags <"$work/commands")"
  [ -z "$unknown" ] && ok "every flag the runbook shows is one its tool's --help names" \
    || bad "every flag the runbook shows is one its tool's --help names ($(tr '\n' ';' <<<"$unknown"))"
  unpriced="$(unpriced_live <"$work/commands")"
  [ -z "$unpriced" ] && ok "every live command in the runbook comes after its own --dry-run form" \
    || bad "every live command in the runbook comes after its own --dry-run form ($(tr '\n' ';' <<<"$unpriced"))"
  for t in 'runnable=yes' '--plugin' 'workspaces/<campaign>/' '--apply' 'bin/report --workspace'; do
    check "the runbook names $t" grep -qF -- "$t" "$work/runbook.md"
  done
fi
# The environment table documents variables the lab reads, and no other.
vars="$(sed -n 's/^| `\([A-Z_][A-Z0-9_]*\)` |.*/\1/p' README.md)"
unread=""
for v in $vars; do
  grep -qlwE -- "$v" bin/* lib/*.sh harnesses/*.sh 2>/dev/null || unread="$unread $v"
done
[ -n "$vars" ] && [ -z "$unread" ] && ok "every variable in README.md's table is read by the lab" \
  || bad "every variable in README.md's table is read by the lab (unread:$unread)"
for v in EVALS_ROOT INVENTORY_PATH WORKSPACES_ROOT; do
  check "README.md's table documents $v" grep -qF -- "| \`$v\` |" README.md
done

# --- the contributor guides --------------------------------------------------

for t in 'evals/<skill>/evals.json' 'descriptions/<skill>.json' '[check:'; do
  check "docs/authoring.md names $t" grep -qF -- "$t" docs/authoring.md
done
for t in indeterminate needs_review '[check:' validation train run_status.json; do
  check "docs/triage.md covers $t" grep -qF -- "$t" docs/triage.md
done
check "descriptions/README.md names descriptions/<skill>.json" grep -qF 'descriptions/<skill>.json' descriptions/README.md
check "descriptions/README.md names bin/optimize-description" grep -qF 'bin/optimize-description' descriptions/README.md
check "descriptions/holdout/README.md names descriptions/holdout/<skill>.json" \
  grep -qF 'descriptions/holdout/<skill>.json' descriptions/holdout/README.md
check "evals/README.md names evals/<skill>/evals.json" grep -qF 'evals/<skill>/evals.json' evals/README.md
check "results/README.md names bin/report" grep -qF 'bin/report' results/README.md
libgaps=""
for f in lib/*.sh; do grep -qF -- "\`$(basename "$f")\`" lib/README.md || libgaps="$libgaps $(basename "$f")"; done
for f in $(grep -oE '`[a-z-]+\.sh`' lib/README.md | tr -d '`' | sort -u); do
  [ -f "lib/$f" ] || [ -f "lib/tests/$f" ] || libgaps="$libgaps $f(absent)"
done
[ -z "$libgaps" ] && ok "lib/README.md names every lib/*.sh and nothing that is gone" \
  || bad "lib/README.md names every lib/*.sh and nothing that is gone:$libgaps"
check "the PR template names bin/evaluate" grep -qF 'bin/evaluate' .github/PULL_REQUEST_TEMPLATE.md

# --- one run has no spread: said in three docs and bin/evaluate --help -------

flat() { tr -s ' \n' ' '; }
nospread=""
for f in README.md results/README.md docs/authoring.md; do
  flat < "$f" | grep -qF 'With one run the stddev means nothing' || flat < "$f" | grep -qF 'with one run the stddev means nothing' \
    || nospread="$nospread $f(stddev)"
  flat < "$f" | grep -qF -- '--runs 3' || nospread="$nospread $f(--runs 3)"
done
ev_help="$(bash bin/evaluate --help | flat)"
grep -qF 'With one run the stddev means nothing; a record uses 3' <<<"$ev_help" || nospread="$nospread bin/evaluate--help(stddev)"
grep -qF -- '--runs 3 --dry-run' <<<"$ev_help" || nospread="$nospread bin/evaluate--help(--runs 3)"
[ -z "$nospread" ] && ok "README, results/README.md, docs/authoring.md and bin/evaluate --help say one run has no stddev and a record uses 3" \
  || bad "the docs say one run has no stddev and a record uses 3 (missing:$nospread)"

exit "$fails"
