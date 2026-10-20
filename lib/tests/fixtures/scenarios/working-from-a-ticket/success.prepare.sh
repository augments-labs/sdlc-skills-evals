# shellcheck shell=bash
# shellcheck disable=SC2154
# The capture's ledger row binds the capture's OWN bytes, so the identity is
# computed here rather than written down: a hard-coded hash would stop
# matching the moment the capture's text changed.
capture=".sdlc-skills/briefs/2026-10-20-inv-77-ticket.md"
identity="$(git hash-object "$capture" | cut -c1-7)"
cat > "${capture%.md}.ledger.md" <<LEDGER
# Decision ledger — INV-77 capture

| Identity | Section | Location | State | Bound evidence | Updated |
| --- | --- | --- | --- | --- | --- |
| $identity |  | $capture | captured | INV-77, read 2026-10-20 through the file the user named | 2026-10-20 |
LEDGER
