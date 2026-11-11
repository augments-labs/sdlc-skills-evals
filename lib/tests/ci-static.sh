#!/usr/bin/env bash
# Offline test: the static gate itself. Checks the `static` workflow's
# invariants, lints and parses every shell file the CI globs match, runs
# every other lib/tests/*.sh suite with the live-CLI tripwire first on PATH,
# proves the tripwire covers every CLI a harness can launch, and runs
# bin/check inside a clean `git archive HEAD` extraction. No live run: an
# agent CLI reached by any suite trips a shim, which records the call and
# fails with 97.
#
# The tripwire is a backstop for suites that inherit PATH.
# lib/tests/harness-adapters.sh resets PATH to its own bin plus /usr/bin:/bin,
# and is covered by its own CLI-resolution assertion.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
self="lib/tests/$(basename "$0")"
cd "$here" || exit 1

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }
note() { printf '  note  %s\n' "$1"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- the workflow: name, job, concurrency, permissions, steps -----------------

wf=.github/workflows/static.yml
has() { grep -qE -- "$1" "$wf"; }
has '^name: static$' && ok "the workflow is named static" || bad "the workflow is named static"
awk '/^jobs:/ { j = 1; next } j && /^[^ ]/ { j = 0 } j && /^  static:$/ { f = 1 } END { exit !f }' "$wf" \
  && ok "the job id is static (the required status check)" || bad "the job id is static (the required status check)"
has '^concurrency:$' && has '^  group: static-\$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}$' \
  && has '^  cancel-in-progress: true$' \
  && ok "runs on one ref cancel each other (concurrency group)" \
  || bad "runs on one ref cancel each other (concurrency group)"
has '^permissions:$' && has '^  contents: read$' && ! has ':[[:space:]]*write' \
  && ok "the token is read-only" || bad "the token is read-only"
! grep -qiE 'secrets\.|api[_-]?key|_TOKEN|ANTHROPIC|OPENAI' "$wf" \
  && ok "no secret or API key reaches the job" || bad "no secret or API key reaches the job"
# A launcher or CLI in command position (a run: line, after bash, &&, ; or |)
# runs; the same name in a file list being linted does not.
cmd='(run:[[:space:]]*(\|[[:space:]]*)?|bash[[:space:]]+|&&[[:space:]]*|;[[:space:]]*|\|[[:space:]]*)'
! grep -qE "${cmd}(\./)?bin/(evaluate|optimize-description|triggering)([[:space:]]|\$)|--harness|--dangerously|--yolo|--approve-for-me|${cmd}(agy|claude|codex|cursor-agent|devin|grok|hermes|kimi|muse|opencode|pi)([[:space:]]|\$)" "$wf" \
  && ok "no live launcher, agent CLI, or dangerous-mode flag runs in CI" \
  || bad "no live launcher, agent CLI, or dangerous-mode flag runs in CI"
globs='bin/* lib/*.sh lib/tests/*.sh lib/tests/fake-cli/*.sh harnesses/*.sh fixtures/*.sh'
tr -s ' \n' ' ' < "$wf" | grep -qF "shellcheck -S warning $globs" \
  && ok "shellcheck -S warning lints every shell glob" || bad "shellcheck -S warning lints every shell glob"
has 'run: bash bin/check$' && ok "the workflow runs bin/check" || bad "the workflow runs bin/check"
has "run: bash $self\$" && ok "the suite step is bash $self" || bad "the suite step is bash $self"
has 'test -z "\$\(git status --porcelain\)"' \
  && ok "the workflow fails a run that dirties the tree" || bad "the workflow fails a run that dirties the tree"
arch=1
has 'git archive HEAD' || arch=0
for v in SDLC_SKILLS_ROOT INVENTORY_PATH DOCS_ROOT DESCRIPTIONS_ROOT EVALS_ROOT; do
  has "-u $v( |$)" || arch=0
done
has 'env -u .* bash bin/check' || arch=0
[ "$arch" = 1 ] && ok "the workflow runs bin/check in a git archive HEAD extraction, root overrides unset" \
  || bad "the workflow runs bin/check in a git archive HEAD extraction, root overrides unset"

# --- every shell file the CI globs match parses, and lints when it can --------

# shellcheck disable=SC2086  # $globs is word-split and globbed on purpose
set -- $globs
unparsed=""
for f in "$@"; do
  [ -f "$f" ] || { unparsed="$unparsed $f(missing)"; continue; }
  bash -n "$f" 2>/dev/null || unparsed="$unparsed $f"
done
[ -z "$unparsed" ] && ok "bash -n passes on all $# files the CI globs match" \
  || bad "bash -n passes on every file the CI globs match:$unparsed"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$@" > "$work/shellcheck.out" 2>&1 \
    && ok "shellcheck -S warning is clean on all $# files" \
    || bad "shellcheck -S warning is clean ($(grep -c '^In ' "$work/shellcheck.out") finding(s): $(grep -m3 '^In ' "$work/shellcheck.out" | tr '\n' ' '))"
else
  ok "shellcheck not on PATH here: lint left to the workflow's shellcheck step"
fi

# --- the tripwire: one shim per CLI a harness can launch ---------------------

clis="$(grep -ohE '(command -v|require_tool) [a-z][a-z0-9-]*|[a-z]+_exec [a-z][a-z0-9-]*' harnesses/*.sh \
  | awk '{print $NF}' | sort -u)"
shims="$(cd lib/tests/tripwire && ls -A | sort)"
[ -n "$clis" ] && [ "$clis" = "$shims" ] \
  && ok "the shim set equals the $(wc -l <<<"$clis") CLI names the harnesses launch" \
  || bad "the shim set equals the CLI names the harnesses launch (harnesses: $(tr '\n' ' ' <<<"$clis"); shims: $(tr '\n' ' ' <<<"$shims"))"
broken=""
for s in lib/tests/tripwire/*; do
  n="$(basename "$s")"; log="$work/trip-$n.log"
  [ -x "$s" ] && bash -n "$s" 2>/dev/null || { broken="$broken $n(not executable or does not parse)"; continue; }
  TRIPWIRE_LOG="$log" "$s" --probe >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 97 ] && grep -qx "$n --probe" "$log" 2>/dev/null || broken="$broken $n(rc $rc)"
done
[ -z "$broken" ] && ok "every shim is executable, parses, records its call, and exits 97" \
  || bad "every shim is executable, parses, records its call, and exits 97:$broken"

# --- every other suite, under the tripwire ----------------------------------

tree_before="$(git status --porcelain 2>/dev/null)"
trip="$(mktemp)"   # absolute and outside the repo: the clean-tree check stays valid
failed_suites=""
leaky_suites=""
for t in lib/tests/*.sh; do
  [ "$t" = "$self" ] && continue
  # Each suite gets a TMPDIR of its own, empty, so what it leaves there is
  # its own: a suite removes every temp file and directory it creates. A
  # case that unsets TMPDIR runs under /tmp, where only the run-home parent
  # is watched, and only when it is absent before the suite starts; a
  # suite that writes elsewhere under /tmp is not seen.
  suite_tmp="$work/tmp-$(basename "$t" .sh)"
  mkdir -p "$suite_tmp"
  had_parent=0; [ ! -e /tmp/sdlc-skills-evals ] || had_parent=1
  ( export TRIPWIRE_LOG="$trip"; PATH="$here/lib/tests/tripwire:$PATH"; export PATH
    TMPDIR="$suite_tmp"; export TMPDIR
    bash "$t" ) < /dev/null > "$work/suite.out" 2>&1 \
    || { failed_suites="$failed_suites $t"; grep -E '^\s*FAIL' "$work/suite.out" | head -5 | sed 's/^/        /'; }
  left="$(find "$suite_tmp" -mindepth 1 -maxdepth 1 | wc -l)"
  [ "$left" -eq 0 ] || leaky_suites="$leaky_suites $t($left left)"
  [ "$had_parent" -eq 1 ] || [ ! -e /tmp/sdlc-skills-evals ] \
    || leaky_suites="$leaky_suites $t(/tmp/sdlc-skills-evals left)"
  rm -rf "$suite_tmp"
done
[ -z "$failed_suites" ] && ok "every other lib/tests suite passes under the tripwire" \
  || bad "every other lib/tests suite passes under the tripwire (failed:$failed_suites)"
[ -z "$leaky_suites" ] && ok "every other lib/tests suite leaves its TMPDIR empty" \
  || bad "every other lib/tests suite leaves its TMPDIR empty (left behind:$leaky_suites)"
[ ! -s "$trip" ] && ok "no suite reached a real agent CLI (tripwire log empty)" \
  || bad "no suite reached a real agent CLI (tripwire log: $(head -3 "$trip" | tr '\n' ';'))"
rm -f "$trip"

# The two checks below read git state. Outside a git work tree (a git archive
# extraction, which is already the committed state alone) there is nothing to
# compare: say so instead of passing or failing them; the checkout run (CI,
# a worktree) observes both.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  note "the clean-tree and git archive checks are not observed here (not a git work tree)"
  exit "$fails"
fi

[ "$(git status --porcelain 2>/dev/null)" = "$tree_before" ] \
  && ok "the suites leave the working tree as they found it" \
  || bad "the suites leave the working tree as they found it"

# --- bin/check on committed state alone -------------------------------------

if git rev-parse --verify --quiet HEAD >/dev/null; then
  mkdir -p "$work/archive"
  if git archive HEAD | tar -x -C "$work/archive"; then
    ( cd "$work/archive" && env -u SDLC_SKILLS_ROOT -u INVENTORY_PATH -u DOCS_ROOT -u DESCRIPTIONS_ROOT -u EVALS_ROOT \
        bash bin/check ) > "$work/archive.out" 2>&1 \
      && ok "bin/check passes in a clean git archive HEAD extraction" \
      || bad "bin/check passes in a clean git archive HEAD extraction ($(tail -3 "$work/archive.out" | tr '\n' ' '))"
  else
    bad "git archive HEAD extracts"
  fi
else
  bad "a HEAD commit to archive"
fi

exit "$fails"
