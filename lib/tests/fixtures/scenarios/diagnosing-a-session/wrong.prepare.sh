# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong report: a citation names a path that is not the record.
# The pin says every citation is against the transcript field's path, so a
# citation of another file is not a citation of this record.
report=".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
abs="$(pwd)/.agent/sessions/2026-10-16-billing-export.ndjson"
sed -i "s|$abs:6|src/reporting.js:6|g; s|$abs:7|src/reporting.js:7|g; s|$abs:4|src/reporting.js:4|g" "$report"
