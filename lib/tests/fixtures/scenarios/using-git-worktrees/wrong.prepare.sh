# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the edit landed on the shared checkout instead of
# in an owned worktree.
git -C "$d" worktree remove --force "$d/.worktrees/feature" >/dev/null 2>&1 || true
rm -rf "$d/.worktrees"
git -C "$d" worktree prune >/dev/null 2>&1 || true
