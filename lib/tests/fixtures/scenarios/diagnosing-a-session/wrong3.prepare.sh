# shellcheck shell=bash
# shellcheck disable=SC2154
# The wrong report: it DECLARES a transcript that is not the record, while
# its citations still name the record. The declared path has to be the
# record — a report that certifies its own citation path is a report about
# nothing.
report=".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
abs="$(pwd)/.agent/sessions/2026-10-16-billing-export.ndjson"
sed -i "s|^- Transcript: .*|- Transcript: $d/src/reporting.js (8 lines at 2026-10-20 10:02)|" "$report"
