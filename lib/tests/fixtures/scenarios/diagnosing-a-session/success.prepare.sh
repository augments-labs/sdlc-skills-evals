# shellcheck shell=bash
# shellcheck disable=SC2154
# The pinned trace format says the report's `transcript` field holds "the
# absolute path every citation is against". The capture therefore carries the
# absolute path of this workdir's session record, and every citation names it.
#
# The citations are rewritten FIRST: the declared field is then replaced
# wholesale, so neither sed can meet its own replacement.
report=".sdlc-skills/evidence/2026-10-20-billing-export/diagnosis.md"
abs="$(pwd)/.agent/sessions/2026-10-16-billing-export.ndjson"
sed -i "s|\.agent/sessions/2026-10-16-billing-export\.ndjson|$abs|g" "$report"
sed -i "s|^- Transcript: .*|- Transcript: $abs (8 lines at 2026-10-20 10:02)|" "$report"
