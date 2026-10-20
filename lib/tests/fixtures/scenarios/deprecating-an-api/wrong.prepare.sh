# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong record: the use is written as zero. Nothing counts the
# old path, so a zero is a claim the record cannot support.
sed -i 's#| 2026-10-20 | one release cycle | unknown | unknown | nothing counts it |#| 2026-10-20 | one release cycle | 0 | 0 | nothing counts it |#' \
  ".sdlc-skills/designs/2026-10-20-profile-v1-deprecation.md"
