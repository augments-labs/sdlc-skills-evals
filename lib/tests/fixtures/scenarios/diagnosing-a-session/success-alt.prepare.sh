# shellcheck shell=bash
# shellcheck disable=SC2154
# The other conformant report: the RELATIVE form of the transcript path, in
# the declared field and in every citation. The pinned trace format asks for
# the absolute one; the relative one names the same record and has to pass
# too.
report=".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
abs="$(pwd)/.agent/sessions/2026-10-16-billing-export.ndjson"
sed -i "s|$abs|.agent/sessions/2026-10-16-billing-export.ndjson|g" "$report"
