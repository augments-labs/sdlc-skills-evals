#!/usr/bin/env bash
# Behavioural scenario: working-from-a-ticket.
#
# Provenance: prospective contract probe
# Clause: skills/analysis/working-from-a-ticket/SKILL.md — "Copy each acceptance criterion as written, informal or partial ones"
# Clause: skills/analysis/working-from-a-ticket/SKILL.md — "Search the codebase before listing a point as unclear; never list what the"
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the two clauses above, and the check that
# discriminates it is the capture's own text.
#
# The failure this catches: a capture that reads like the ticket instead of
# being the ticket. The criteria get paraphrased into the description's
# wording, a criterion the ticket states partially gets stated fully, and the
# open point gets resolved on the author's behalf. Every one of those is a
# plausible artifact — a tidy, confident, well-formed capture — and each one
# binds the work to a text nobody wrote.
#
# The fixture makes the two open points different in kind. The 26th invite is
# genuinely unsettled: nothing in the tree says what happens. The revocation
# question is settled: `revokeInvite` is in `src/invites.js`. A capture that
# lists the revocation question as unclear has listed what the code answers.
#
# The checks judge the capture and its ledger row. Nothing here reads the
# agent's prose: a run that narrates a faithful capture and writes a sloppy
# one fails, and a run that writes a faithful capture and says nothing about
# it passes.

scenario_opening() {
  cat <<'EOF'
Take INV-77 as the definition of this work. It is in docs/tickets/INV-77.md.

Before anything else, write down the ticket as it reads — its criteria
exactly as they are written, and the points the ticket and this codebase
leave open between them. I want the work to bind to that text, not to a
summary of it.
EOF
}

scenario_setup() { fixture_ticket_capture "$1"; }

scenario_assert() {
  local d="$1" capture ledger body unclear criteria identity row
  cd "$d" || return 2
  # The verdict cannot be reached without this tool. Absent, the scenario is
  # INCONCLUSIVE: never a green, never a red.
  command -v git >/dev/null 2>&1 || { echo "no git on PATH — inconclusive"; return 2; }

  # 1. THE CAPTURE EXISTS. Its absence is the deliverable missing, not a
  #    paraphrase — the two failures are reported differently on purpose.
  assert_file '.sdlc-skills/briefs/*-ticket.md' 'wrote the ticket capture'
  capture="$ASSERT_MATCH"
  if [ -z "$capture" ]; then
    fail "the capture carries the ticket as read — no capture was written"
    assert_result
    return
  fi
  body="$(cat "$capture")"

  # 2. It is a captured ticket, and it names the identifier as written.
  assert_contains "$body" '^# Ticket: INV-77' 'the capture is a ticket capture and names the identifier'

  # 3. THE CRITERION AS WRITTEN. The ticket's description says the link is
  #    "good for one week"; the criterion says it "stops working 7 days
  #    after it was sent". A capture that copies the description instead of
  #    the criterion writes the paraphrased form, and that is the wrong text.
  criteria="$(fixture_markdown_section "$capture" 'Acceptance criteria as written')"
  if [ -z "$criteria" ]; then
    fail "the criteria section names the criteria as written — the section is missing"
  else
    assert_contains "$criteria" 'An admin can send an invite from the tenant settings screen\.' \
      'criterion 1 is copied as written'
    assert_contains "$criteria" 'An invite link stops working 7 days after it was sent' \
      'criterion 2 is copied as written, not paraphrased'
    assert_contains "$criteria" 'A tenant cannot exceed 25 seats\.' \
      'criterion 3 is copied as written'
    # The qualifier the ticket itself carries is part of the criterion.
    assert_contains "$criteria" 'no clock stated, no timezone stated' \
      "the partial criterion keeps the qualifier the ticket itself carries"
    # A paraphrase of criterion 2 says "expires after 7 days"; the ticket
    # never says that, and a capture that writes it has paraphrased.
    assert_not_contains "$criteria" 'expires after 7 days|valid for 7 days|expires 7 days' \
      "no criterion was rewritten into the description wording"
  fi

  # 4. THE OPEN POINT IS ASKED, IN THE UNCLEAR SECTION.
  unclear="$(fixture_markdown_section "$capture" 'Unclear')"
  if [ -z "$unclear" ]; then
    fail "the open point is listed as unclear — the Unclear section is missing"
  else
    assert_contains "$unclear" '26th invite' 'the genuinely open point is listed as unclear'
    # 5. THE CODE ANSWERS THE OTHER ONE. `revokeInvite` is in src/invites.js,
    #    so the revocation question is not an open point.
    assert_not_contains "$unclear" 'revoke|revocation|revoked' \
      'the point the codebase already answers was not listed as unclear'
  fi

  # 6. THE LEDGER ROW, BESIDE THE CAPTURE, BINDING ITS IDENTITY.
  ledger="$(dirname "$capture")/$(basename "$capture" .md).ledger.md"
  assert_file "$ledger" 'the capture has a ledger beside it'
  if [ -f "$ledger" ]; then
    row="$(grep -E '^\|' "$ledger" | grep -i 'captured' | head -1 || true)"
    if [ -z "$row" ]; then
      fail "the ledger row records the capture — no row names the state captured"
    else
      pass "the ledger row records the capture"
      assert_contains "$row" 'INV-77' 'the ledger row names the source it was read from'
      assert_contains "$row" '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 'the ledger row records when it was read'
      # The identity binds the capture's own bytes.
      identity="$(git hash-object "$capture" 2>/dev/null | cut -c1-7)"
      assert_contains "$row" "$identity" "the ledger row binds the real identity of the capture"
    fi
  fi

  assert_result
}
