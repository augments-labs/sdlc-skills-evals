#!/usr/bin/env bash
# Offline test: plugin pinning by path or ref. Builds its own throwaway
# plugin stand-in, so no sibling checkout is needed. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../pin.sh
source "$here/../pin.sh"

fails=0
ok() { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=1; }

standin="$(mktemp -d)"
idrepo="$(mktemp -d)"; idwork="$(mktemp -d)"
trap 'rm -rf "$standin" "$idrepo" "$idwork"' EXIT
git -C "$standin" init -q
git -C "$standin" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
commit="$(git -C "$standin" rev-parse HEAD)"
export SDLC_SKILLS_ROOT="$standin"

# pinning by ref prints the commit and cleans up at shell exit
run_dir="$(mktemp -d)"
got="$(lab_pin_plugin "$commit" "$run_dir")"
[ "$got" = "$commit" ] && ok "pin by ref prints the commit" || bad "pin by ref prints the commit (got $got)"
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "captured pin leaves no worktree behind" || bad "captured pin leaves no worktree behind"
rm -rf "$run_dir"

# a same-shell pin (no capture) persists until explicit cleanup
run_dir_s="$(mktemp -d)"
lab_pin_plugin "$commit" "$run_dir_s" >"$run_dir_s/commit.txt"
[ "$(cat "$run_dir_s/commit.txt")" = "$commit" ] \
  && ok "same-shell pin prints the commit" || bad "same-shell pin prints the commit"
[ -n "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "same-shell pin persists" || bad "same-shell pin persists"
lab_pin_cleanup "$run_dir_s"
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "pin cleanup leaves no worktree behind" || bad "pin cleanup leaves no worktree behind"
rm -rf "$run_dir_s"

# pinning by directory uses it as is and prints its commit
run_dir2="$(mktemp -d)"
got2="$(lab_pin_plugin "$standin" "$run_dir2")"
[ "$got2" = "$commit" ] && ok "pin by directory prints its commit" || bad "pin by directory prints its commit (got $got2)"
rm -rf "$run_dir2"

# an unknown ref is refused, never resolved to something else
run_dir3="$(mktemp -d)"
if lab_pin_plugin "does-not-exist-sdlc-skills-evals" "$run_dir3" >/dev/null 2>&1; then
  bad "unknown ref is refused"
else
  ok "unknown ref is refused"
fi
[ -z "$(git -C "$standin" worktree list --porcelain | grep '^worktree' | sed 1d)" ] \
  && ok "refused pin leaves no worktree behind" || bad "refused pin leaves no worktree behind"
rm -rf "$run_dir3"

# no plugin root anywhere is refused, never a global install
run_dir4="$(mktemp -d)"
if SDLC_SKILLS_ROOT=/nonexistent/sdlc-skills-evals-root lab_pin_plugin "$commit" "$run_dir4" >/dev/null 2>&1; then
  bad "missing plugin root is refused"
else
  ok "missing plugin root is refused"
fi
rm -rf "$run_dir4"

# --- the committed upstream pin ----------------------------------------------
#
# The pin a run resolves is a COMMIT, never a mutable tag: it comes from the
# committed inventory, and a value that is not a full object name is
# refused, so no run can select new work from a tag.

lab_root="$(cd "$here/../.." && pwd)"
inv="$lab_root/config/upstream-inventory.json"

pin="$(lab_inventory_commit 2>/dev/null)"
if [ -n "$pin" ] && [ "${#pin}" -eq 40 ]; then
  ok "the committed pin is a full object name"
else
  bad "the committed pin is a full object name (got '$pin')"
fi
case "$pin" in
  *[!0-9a-f]*) bad "the committed pin is hexadecimal" ;;
  *) ok "the committed pin is hexadecimal" ;;
esac

# a version tag in place of the commit is refused
tag_inv="$standin/inventory-tag.json"
jq '.upstream.commit = "v11.0.0"' "$inv" >"$tag_inv" 2>/dev/null
if INVENTORY_PATH="$tag_inv" lab_inventory_commit >/dev/null 2>&1; then
  bad "a version tag instead of a commit is refused"
else
  ok "a version tag instead of a commit is refused"
fi

# a missing inventory is refused
if INVENTORY_PATH="$standin/no-such-inventory.json" lab_inventory_commit >/dev/null 2>&1; then
  bad "a missing inventory is refused"
else
  ok "a missing inventory is refused"
fi

# --- what a ref names --------------------------------------------------------
#
# A full object name IS a commit and is taken at face value, so a pinned
# commit needs no checkout to name. A tag is resolved to the commit it
# names. A path is its own HEAD.

face="$(SDLC_SKILLS_ROOT=/nonexistent/sdlc-skills-evals-root lab_pin_commit_of "$commit" 2>/dev/null)"
[ "$face" = "$commit" ] && ok "a commit is taken at face value" \
  || bad "a commit is taken at face value (got '$face')"

git -C "$standin" tag -f selftest-tag "$commit" >/dev/null 2>&1
tagged="$(lab_pin_commit_of selftest-tag 2>/dev/null)"
[ "$tagged" = "$commit" ] && ok "a tag resolves to the commit it names" \
  || bad "a tag resolves to the commit it names (got '$tagged')"

head_of="$(lab_pin_commit_of "$standin" 2>/dev/null)"
[ "$head_of" = "$commit" ] && ok "a path resolves to its own HEAD" \
  || bad "a path resolves to its own HEAD (got '$head_of')"

if lab_pin_commit_of does-not-exist-sdlc-skills-evals >/dev/null 2>&1; then
  bad "an unknown ref is refused"
else
  ok "an unknown ref is refused"
fi

# --- what a run installs -----------------------------------------------------
#
# A reference names a TREE. A ref is pinned into a throwaway worktree, so
# the tree is the commit it names; a directory is the operator's own
# working tree, used as it is, so the tree is the path.

tree_dir="$(lab_pin_tree "$standin" 2>/dev/null)"
[ "$tree_dir" = "$standin" ] && ok "a directory names the tree a run installs" \
  || bad "a directory names the tree a run installs (got '$tree_dir')"
tree_commit="$(lab_pin_tree "$commit" 2>/dev/null)"
[ "$tree_commit" = "$commit" ] && ok "a commit names the tree a run installs" \
  || bad "a commit names the tree a run installs (got '$tree_commit')"
tree_tag="$(lab_pin_tree selftest-tag 2>/dev/null)"
[ "$tree_tag" = "$commit" ] && ok "a tag names the commit it pins to" \
  || bad "a tag names the commit it pins to (got '$tree_tag')"

note_dir="$(lab_pin_note --plugin "$standin" 2>/dev/null)"
[ "$note_dir" = "--plugin $standin; working tree at $commit" ] \
  && ok "a directory's note names the tree and where it is" \
  || bad "a directory's note names the tree and where it is (got '$note_dir')"
note_ref="$(lab_pin_note --plugin selftest-tag 2>/dev/null)"
[ "$note_ref" = "--plugin selftest-tag" ] && ok "a ref's note names the reference" \
  || bad "a ref's note names the reference (got '$note_ref')"
note_base="$(lab_pin_note --base selftest-tag 2>/dev/null)"
[ "$note_base" = "--base selftest-tag" ] && ok "a note names the flag it came from" \
  || bad "a note names the flag it came from (got '$note_base')"

# --- which skill text a reference names --------------------------------------
#
# lab_pin_identity <path|ref> <skill> prints {commit, skill_tree}: the commit
# the tree comes from, and the git tree hash of the skill's directory at that
# commit. The tree hash names the skill text by content, so it survives a
# squash merge that changes the commit. A directory is identified only when it
# is the top of a git work tree whose skill directory is exactly HEAD's; any
# other directory is {null, null}, never a guess. A reference whose commit
# lacks the skill keeps its commit and has a null skill_tree.

gc() { git -C "$idrepo" -c user.name=t -c user.email=t@example.invalid "$@"; }
mkdir -p "$idrepo/skills/common/probe" "$idrepo/skills/flat" "$idrepo/skills/a/twin" "$idrepo/skills/b/twin" "$idrepo/sub"
printf -- '---\nname: probe\ndescription: "probe one"\n---\n' > "$idrepo/skills/common/probe/SKILL.md"
printf -- '---\nname: flat\ndescription: "flat"\n---\n' > "$idrepo/skills/flat/SKILL.md"
printf 'twin\n' | tee "$idrepo/skills/a/twin/SKILL.md" > "$idrepo/skills/b/twin/SKILL.md"
printf 'other\n' > "$idrepo/other.txt"
git -C "$idrepo" init -q
gc add -A && gc commit -q -m one
id_commit="$(git -C "$idrepo" rev-parse HEAD)"
id_tree="$(git -C "$idrepo" rev-parse "HEAD:skills/common/probe")"
flat_tree="$(git -C "$idrepo" rev-parse "HEAD:skills/flat")"
git -C "$idrepo" tag id-tag "$id_commit"
ident() { # $1 path|ref $2 skill [$3 file for the reason] — prints the identity, compact
  SDLC_SKILLS_ROOT="$idrepo" lab_pin_identity "$1" "$2" 2>"${3:-/dev/null}" | jq -c . 2>/dev/null
}
want="$(jq -nc --arg c "$id_commit" --arg t "$id_tree" '{commit: $c, skill_tree: $t}')"
none='{"commit":null,"skill_tree":null}'

got="$(ident "$id_commit" probe)"
[ "$got" = "$want" ] && ok "a commit names the skill's tree at skills/<phase>/<name>" \
  || bad "a commit names the skill's tree at skills/<phase>/<name> (got '$got')"
got="$(ident id-tag probe)"
[ "$got" = "$want" ] && ok "a tag is recorded as the commit it names" \
  || bad "a tag is recorded as the commit it names (got '$got')"
got="$(ident "$id_commit" flat)"
[ "$got" = "$(jq -nc --arg c "$id_commit" --arg t "$flat_tree" '{commit: $c, skill_tree: $t}')" ] \
  && ok "a skill at skills/<name> is found too" || bad "a skill at skills/<name> is found too (got '$got')"
got="$(ident "$id_commit" nosuch "$idwork/reason")"
[ "$got" = "$(jq -nc --arg c "$id_commit" '{commit: $c, skill_tree: null}')" ] \
  && [ -s "$idwork/reason" ] \
  && ok "a commit without the skill has no skill tree, and says why" \
  || bad "a commit without the skill has no skill tree, and says why (got '$got')"
rm -f "$idwork/reason"
got="$(ident "$id_commit" twin)"
[ "$got" = "$(jq -nc --arg c "$id_commit" '{commit: $c, skill_tree: null}')" ] \
  && ok "a skill name two directories carry names no tree" \
  || bad "a skill name two directories carry names no tree (got '$got')"
got="$(ident does-not-exist-sdlc-skills-evals probe)"
[ "$got" = "$none" ] && ok "an unknown ref has no identity" || bad "an unknown ref has no identity (got '$got')"

# a clean work tree is its HEAD
got="$(ident "$idrepo" probe)"
[ "$got" = "$want" ] && ok "a clean work tree is identified by its HEAD and the skill's tree" \
  || bad "a clean work tree is identified by its HEAD and the skill's tree (got '$got')"
# dirt outside the skill's directory leaves the skill text what HEAD says
printf 'changed\n' >> "$idrepo/other.txt"; printf 'x\n' >> "$idrepo/skills/flat/SKILL.md"
got="$(ident "$idrepo" probe)"
[ "$got" = "$want" ] && ok "a change outside the skill's directory does not unname it" \
  || bad "a change outside the skill's directory does not unname it (got '$got')"
# an edited or an untracked file inside it does
got="$(ident "$idrepo" flat "$idwork/reason")"
[ "$got" = "$none" ] && [ -s "$idwork/reason" ] \
  && ok "an edited skill directory has no identity, and says why" \
  || bad "an edited skill directory has no identity, and says why (got '$got')"
rm -f "$idwork/reason"
printf 'new\n' > "$idrepo/skills/common/probe/notes.md"
got="$(ident "$idrepo" probe)"
[ "$got" = "$none" ] && ok "an untracked file in the skill directory has no identity" \
  || bad "an untracked file in the skill directory has no identity (got '$got')"
# the run installs an untracked file whether or not git is set to list it
git -C "$idrepo" config status.showUntrackedFiles no
got="$(ident "$idrepo" probe)"
[ "$got" = "$none" ] && ok "an untracked file has no identity even when git is set not to list untracked files" \
  || bad "an untracked file has no identity even when git is set not to list untracked files (got '$got')"
git -C "$idrepo" config --unset status.showUntrackedFiles
rm -f "$idrepo/skills/common/probe/notes.md"
# so does a file git ignores, and a tracked file git is told not to look at:
# plain `git status` prints nothing for either, and the run installs both
mkdir -p "$idrepo/.git/info"; printf 'scratch.md\n' >> "$idrepo/.git/info/exclude"
printf 'new\n' > "$idrepo/skills/common/probe/scratch.md"
got="$(ident "$idrepo" probe "$idwork/reason")"
[ "$got" = "$none" ] && grep -q 'ignored' "$idwork/reason" \
  && ok "an ignored file in the skill directory has no identity, and says why" \
  || bad "an ignored file in the skill directory has no identity, and says why (got '$got': $(cat "$idwork/reason"))"
rm -f "$idrepo/skills/common/probe/scratch.md" "$idwork/reason"
for flag in assume-unchanged skip-worktree; do
  git -C "$idrepo" update-index "--$flag" skills/common/probe/SKILL.md
  printf 'edited unseen\n' >> "$idrepo/skills/common/probe/SKILL.md"
  got="$(ident "$idrepo" probe "$idwork/reason")"
  [ "$got" = "$none" ] && grep -q "$flag" "$idwork/reason" \
    && ok "a tracked file edited under --$flag has no identity, and says why" \
    || bad "a tracked file edited under --$flag has no identity, and says why (got '$got': $(cat "$idwork/reason"))"
  git -C "$idrepo" update-index "--no-$flag" skills/common/probe/SKILL.md
  git -C "$idrepo" checkout -q -- skills/common/probe/SKILL.md
  rm -f "$idwork/reason"
done
got="$(ident "$idrepo" probe)"
[ "$got" = "$want" ] && ok "with the file and the flags gone, the work tree is its HEAD again" \
  || bad "with the file and the flags gone, the work tree is its HEAD again (got '$got')"
# a tree hash covers file modes, so a mode HEAD does not hold is a difference
# even where git is told not to look at modes
git -C "$idrepo" config core.fileMode false
chmod +x "$idrepo/skills/common/probe/SKILL.md"
got="$(ident "$idrepo" probe "$idwork/reason")"
[ "$got" = "$none" ] && grep -q 'uncommitted' "$idwork/reason" \
  && ok "a file mode HEAD does not hold has no identity under core.fileMode=false" \
  || bad "a file mode HEAD does not hold has no identity under core.fileMode=false (got '$got': $(cat "$idwork/reason" 2>/dev/null))"
chmod -x "$idrepo/skills/common/probe/SKILL.md"; rm -f "$idwork/reason"
got="$(ident "$idrepo" probe)"
[ "$got" = "$want" ] && ok "with HEAD's mode back, the work tree is its HEAD under core.fileMode=false" \
  || bad "with HEAD's mode back, the work tree is its HEAD under core.fileMode=false (got '$got')"
git -C "$idrepo" config --unset core.fileMode
# a work tree git cannot report on is not a clean one, and the reason is git's
broken="$idwork/broken"; git clone -q "$idrepo" "$broken"
printf 'not an index\n' > "$broken/.git/index"
got="$(ident "$broken" probe "$idwork/reason")"
[ "$got" = "$none" ] && grep -q 'git status failed' "$idwork/reason" \
  && ! grep -q 'uncommitted' "$idwork/reason" \
  && ok "a work tree git status fails on has no identity, and the reason is not 'uncommitted changes'" \
  || bad "a work tree git status fails on has no identity, and the reason is not 'uncommitted changes' (got '$got': $(cat "$idwork/reason"))"
rm -rf "$broken" "$idwork/reason"
# a directory that is not the top of a git work tree is not a commit's tree
got="$(ident "$idrepo/sub" probe "$idwork/reason")"
grep -q 'not the top of a git work tree' "$idwork/reason" \
  && ok "a subdirectory is told it is not the top of a work tree" \
  || bad "a subdirectory is told it is not the top of a work tree ($(cat "$idwork/reason"))"
[ "$got" = "$none" ] && ok "a subdirectory of a work tree has no identity" \
  || bad "a subdirectory of a work tree has no identity (got '$got')"
plain="$idwork/plain"; mkdir -p "$plain/skills/probe"
cp "$idrepo/skills/common/probe/SKILL.md" "$plain/skills/probe/SKILL.md"
got="$(GIT_CEILING_DIRECTORIES="$idwork" ident "$plain" probe "$idwork/reason")"
[ "$got" = "$none" ] && grep -q 'git cannot read it as a work tree' "$idwork/reason" \
  && grep -qi 'not a git repository' "$idwork/reason" \
  && ok "a directory that is no git work tree has no identity, and the reason carries git's own" \
  || bad "a directory that is no git work tree has no identity, and the reason carries git's own (got '$got': $(cat "$idwork/reason"))"
rm -rf "$plain"

# the same skill text under another commit keeps its tree hash: what a
# squash merge leaves behind still matches the record
gc checkout -q -- . && gc commit -q --allow-empty -m two
got="$(ident "$(git -C "$idrepo" rev-parse HEAD)" probe)"
[ "$(jq -r .skill_tree <<<"$got")" = "$id_tree" ] && [ "$(jq -r .commit <<<"$got")" != "$id_commit" ] \
  && ok "the skill tree is the same under a different commit" \
  || bad "the skill tree is the same under a different commit (got '$got')"

# --- which description a tree carries -----------------------------------------
#
# lab_description_sha256 <SKILL.md> prints the SHA-256 of the exact bytes of
# the frontmatter line that begins `description:`, without its newline. The
# plugin's CI computes the same value, so the bytes are pinned here against
# sha256sum on the literal line.

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
dfile="$idwork/SKILL.md"
printf -- '---\nname: probe\ndescription: "probe one"\nlicense: x\n---\n\ndescription: body line\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"
[ "$got" = "$(sha 'description: "probe one"')" ] \
  && ok "the description line is hashed without its newline" \
  || bad "the description line is hashed without its newline (got '$got')"
[ "$got" != "$(printf 'description: "probe one"\n' | sha256sum | cut -d' ' -f1)" ] \
  && ok "the newline is not part of the hash" || bad "the newline is not part of the hash"
printf -- '---\nname: probe\n---\n\ndescription: body line\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"; rc=$?
[ -z "$got" ] && [ "$rc" -ne 0 ] \
  && ok "a description: line outside the frontmatter is not the description" \
  || bad "a description: line outside the frontmatter is not the description (got '$got', rc $rc)"
printf 'description: no frontmatter\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"; rc=$?
[ -z "$got" ] && [ "$rc" -ne 0 ] \
  && ok "a file with no frontmatter has no description hash" \
  || bad "a file with no frontmatter has no description hash (got '$got', rc $rc)"
printf -- '---\n  description: nested\ndescription: first\ndescription: second\n---\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"
[ "$got" = "$(sha 'description: first')" ] \
  && ok "the first line that begins description: is the one hashed" \
  || bad "the first line that begins description: is the one hashed (got '$got')"
# every byte of the line but its LF counts: trailing spaces and a CR included
printf -- '---\ndescription: padded  \r\n---\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"
[ "$got" = "$(printf 'description: padded  \r' | sha256sum | cut -d' ' -f1)" ] \
  && ok "trailing bytes before the newline are hashed as they are" \
  || bad "trailing bytes before the newline are hashed as they are (got '$got')"
printf -- '---\ndescription: caf\303\251 \342\200\224 dash\n---\n' > "$dfile"
got="$(lab_description_sha256 "$dfile")"
[ "$got" = "$(printf 'description: caf\303\251 \342\200\224 dash' | sha256sum | cut -d' ' -f1)" ] \
  && ok "non-ASCII bytes are hashed as they are" \
  || bad "non-ASCII bytes are hashed as they are (got '$got')"
got="$(lab_description_sha256 "$idwork/no-such-file")"; rc=$?
[ -z "$got" ] && [ "$rc" -ne 0 ] && ok "a missing SKILL.md has no description hash" \
  || bad "a missing SKILL.md has no description hash (got '$got', rc $rc)"

exit "$fails"
