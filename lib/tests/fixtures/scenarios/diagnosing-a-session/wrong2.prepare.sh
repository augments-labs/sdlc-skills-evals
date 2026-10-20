# shellcheck shell=bash
# shellcheck disable=SC2154
# The other wrong report: the credential is copied into it instead of being
# named by its kind and its line.
report=".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
sed -i 's|The value itself is not copied here: it is a credential, on|the value is sk-live-SYNTHETIC-FIXTURE-NOT-A-REAL-KEY-0000, a credential, on|' "$report"
