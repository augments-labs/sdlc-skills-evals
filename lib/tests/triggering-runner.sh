#!/usr/bin/env bash
# Offline test: bin/triggering via the fake harness only. The fake emits a
# fixed SKILL line (FAKE_SUBJECT) or none (FAKE_FIRE=0), so the scoring
# loop's reductions are exercised with zero live calls. No token spent.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fake_h="$here/lib/tests/fake-cli"
export SDLC_SKILLS_EVALS_ROOT="$here"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$standin" "$work"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
plug_commit="$(git -C "$standin" rev-parse HEAD)"

# the pin a run resolves when the caller names none
inv_commit="$(jq -r '.upstream.commit' "$here/config/upstream-inventory.json")"

base=(--harness fake --harness-dir "$fake_h" --plugin "$standin")

# --dry-run prices without pinning or calling anything (no --plugin needed)
out="$("$here/bin/triggering" --harness fake --skill yagni --dry-run 2>&1)"
[ "$?" -eq 0 ] && printf '%s' "$out" | grep -qE "[0-9]+ (calls|invocations)" \
  && ok "dry-run prices without calling" || bad "dry-run prices without calling"

# firing fake: positives pass, negatives fail, sheet exits 1
out="$(FAKE_FIRE=1 FAKE_SUBJECT=yagni "$here/bin/triggering" "${base[@]}" \
  --skill yagni --split train --runs 1 --jobs 2 2>&1)"
rc="$?"
[ "$rc" -eq 1 ] && ok "mixed sheet exits 1" || bad "mixed sheet exits 1 (got $rc)"
printf '%s' "$out" | grep -q "PASS" && ok "positives pass" || bad "positives pass"
printf '%s' "$out" | grep -q "should have routed to" \
  && ok "negative failures name the route" || bad "negative failures name the route"

# silent fake: positives miss with the observed-routing diagnostic
out="$(FAKE_FIRE=0 "$here/bin/triggering" "${base[@]}" \
  --skill yagni --split train --runs 1 --jobs 2 2>&1)"
printf '%s' "$out" | grep -q "expected yagni to fire | observed: (nothing routed)" \
  && ok "misses name the observation" || bad "misses name the observation"

# an empty split scores nothing and passes
out="$("$here/bin/triggering" "${base[@]}" --skill yagni --split holdout --runs 1 2>&1)"
[ "$?" -eq 0 ] && printf '%s' "$out" | grep -q "no queries in this split" \
  && ok "empty split is quiet" || bad "empty split is quiet"

# an unrunnable harness measures nothing, via exit 2 before any launch
out="$("$here/bin/triggering" --harness codex --skill yagni --dry-run 2>&1)"
[ "$?" -eq 0 ] || bad "dry-run ignores harness runnable state"
"$here/bin/triggering" --harness codex --skill yagni --plugin "$standin" --runs 1 >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "unrunnable harness exits 2" || bad "unrunnable harness exits 2"

# --- the pin a run resolves --------------------------------------------------
#
# The default plugin is the committed upstream commit: a commit, never a
# moving branch. The dry run names it, and names the exact command a live
# run would be, without pinning, calling or launching anything.

out="$("$here/bin/triggering" --harness fake --skill yagni --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "the dry run names the pinned commit" || bad "the dry run names the pinned commit"
printf '%s' "$out" | grep -qF "command  : bin/triggering --harness fake --skill yagni --plugin $inv_commit" \
  && ok "the dry run names the exact planned invocation" \
  || bad "the dry run names the exact planned invocation"

# an explicit plugin is named as it was given
out="$("$here/bin/triggering" --harness fake --skill yagni --plugin "$standin" --dry-run 2>&1)"
printf '%s' "$out" | grep -qF "command  : bin/triggering --harness fake --skill yagni --plugin $standin" \
  && ok "the dry run names the plugin the caller gave" \
  || bad "the dry run names the plugin the caller gave"

# a run that cannot resolve the default pin says so instead of running
# something else
out="$(SDLC_SKILLS_ROOT="$standin" "$here/bin/triggering" --harness fake --harness-dir "$fake_h" \
  --skill yagni --runs 1 --split train 2>&1)"
rc="$?"
[ "$rc" -eq 2 ] && ok "a run that cannot resolve the default pin refuses" \
  || bad "a run that cannot resolve the default pin refuses (exit $rc)"
printf '%s' "$out" | grep -qF "$inv_commit" \
  && ok "the refusal names the pinned commit" || bad "the refusal names the pinned commit"

# a one-query set, so a live run costs one observation and not a whole
# sheet
desc_work="$work/descriptions/common"
mkdir -p "$desc_work"
printf '%s\n' '[{"query":"probe","should_trigger":true,"split":"train","expect":"probe"}]' \
  >"$desc_work/probe.json"

# a run pinned by commit uses a pinned tree, not the moving checkout
printf 'pinned\n' >"$standin/pinned-marker.txt"
git -C "$standin" add -A
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q -m marker
plug_commit="$(git -C "$standin" rev-parse HEAD)"
launch_log="$work/launch.log"
out="$(SDLC_SKILLS_ROOT="$standin" FAKE_LAUNCH_LOG="$launch_log" \
  DESCRIPTIONS_ROOT="$work/descriptions" \
  "$here/bin/triggering" --harness fake --harness-dir "$fake_h" --skill probe \
  --plugin "$plug_commit" --runs 1 --split train 2>&1)"
printf '%s' "$out" | grep -qF "$plug_commit" \
  && ok "a live run names the pin it resolved" || bad "a live run names the pin it resolved"
install_path="$(sed -n 's/^install //p' "$launch_log" 2>/dev/null | head -1)"
if [ -n "$install_path" ] && [ "$install_path" != "$standin" ]; then
  ok "a run pinned by commit does not use the moving checkout"
else
  bad "a run pinned by commit does not use the moving checkout (installed '$install_path')"
fi

# --- the non-launching paths -------------------------------------------------
#
# A sentinel real CLI stands on PATH: it fails and records that it was
# called. The help and the dry run must never reach it.

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

"$here/bin/triggering" --help >/dev/null 2>&1
"$here/bin/triggering" --harness opencode --skill yagni --dry-run >/dev/null 2>&1
[ ! -f "$sentinel_log" ] && ok "help and the dry run call no CLI" \
  || bad "help and the dry run call no CLI (the sentinel was called)"

# the control: the live path DOES reach the CLI, so the case above is not
# vacuous. The sentinel fails, so nothing is spent.
DESCRIPTIONS_ROOT="$work/descriptions" \
  "$here/bin/triggering" --harness opencode --skill probe --plugin "$standin" \
  --runs 1 --split train >/dev/null 2>&1
[ -f "$sentinel_log" ] && ok "the live path reaches the CLI (the control)" \
  || bad "the live path reaches the CLI (the control)"

exit "$fails"
