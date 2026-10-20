# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong review: the finding cites the BASE revision's line for
# the changed file. At the head that line holds something else.
sed -i 's|Where: `src/auth.js:16` at the head revision|Where: `src/auth.js:12` at the head revision|' \
  ".sdlc-skills/evidence/2026-10-20-pr-42/review.md"
