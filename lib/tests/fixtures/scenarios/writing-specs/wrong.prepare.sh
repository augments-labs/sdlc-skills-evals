# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong spec: the criterion is stated in prose and names no
# artifact that verifies it, so a reader cannot get from the requirement to
# the check in one hop.
sed -i 's#`test/ratelimit.test.js`#a future gate#g; s#`ratelimit.test.js`#a future gate#g' \
  ".sdlc-skills/specs/2026-10-20-rate-limiting.md"
