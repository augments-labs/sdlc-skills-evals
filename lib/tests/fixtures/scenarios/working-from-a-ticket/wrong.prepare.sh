# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong capture: criterion 2 is paraphrased into the wording
# the ticket's description uses. Everything else is the success capture, and
# the ledger still binds the capture it ships with.
capture=".sdlc-skills/briefs/2026-10-20-inv-77-ticket.md"
sed -i 's|An invite link stops working 7 days after it was sent\.|An invite link expires after 7 days.|' "$capture"
identity="$(git hash-object "$capture" | cut -c1-7)"
cat > "${capture%.md}.ledger.md" <<LEDGER
# Decision ledger — INV-77 capture

| Identity | Section | Location | State | Bound evidence | Updated |
| --- | --- | --- | --- | --- | --- |
| $identity |  | $capture | captured | INV-77, read 2026-10-20 through the file the user named | 2026-10-20 |
LEDGER
