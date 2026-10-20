# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong report: the credential is copied into the report
# instead of being named by its kind and its line.
sed -i 's|The value itself is not copied here: it is a credential, on|the value is sk-live-9f3ac71b0e5d42c8, a credential, on|' \
  ".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
