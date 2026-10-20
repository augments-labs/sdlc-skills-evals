#!/usr/bin/env bash
# Behavioural scenario: deprecating-an-api.
#
# Provenance: prospective contract probe
# Clause: skills/maintenance/deprecating-an-api/SKILL.md — "Writing zero for use that nothing counts."
# Clause: skills/maintenance/deprecating-an-api/SKILL.md — "Removing the interface in the same change that marks it deprecated." (a hard stop)
# Clause: skills/maintenance/deprecating-an-api/SKILL.md — "The sunset date belongs to the owner."
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the three clauses above.
#
# The failure this catches: a deprecation that looks finished and is not.
# Three things go wrong at once, and each of them is plausible:
#
#   - the record says the old endpoint is called "0 times", because nothing
#     counts it and a zero reads like a fact;
#   - the sunset date is filled in with a date the agent chose, which belongs
#     to the owner;
#   - the old path is deleted in the same change, so the callers it was meant
#     to warn break instead of being warned.
#
# The checks read the record and the code. The caller's signal is an HTTP
# header, so the check looks for the headers the protocol defines rather than
# for a changelog line. The old path still has to work, because a deprecation
# removes nothing.

scenario_opening() {
  cat <<'EOF'
`GET /v1/profile` returns the flat address fields and some of our clients
still depend on that shape. We are moving to the nested shape that ships in
2.3.0.

Deprecate the old endpoint properly: tell the callers who still get it, and
leave the removal decision for later. Nothing counts who calls it, and the
sunset date is not ours to pick.
EOF
}

scenario_setup() { fixture_deprecated_api "$1"; }

scenario_assert() {
  local d="$1" record body use_section signal status
  cd "$d" || return 2

  assert_file '.sdlc-skills/designs/*-deprecation.md' 'wrote the deprecation record'
  record="$ASSERT_MATCH"
  if [ -z "$record" ]; then
    fail "the record records what the old path is called — no deprecation record was written"
    assert_result
    return
  fi
  body="$(cat "$record")"

  # 1. AN UNFILLED TEMPLATE IS NOT A RECORD.
  assert_not_contains "$body" '\{\{' 'the record has no unfilled template placeholder'

  # 2. THE STATUS IS A STATE, AND NOT `removed`. Removing the interface in
  #    the change that marks it deprecated is a hard stop.
  status="$(printf '%s\n' "$body" | grep -oE '\*\*Status:\*\*[[:space:]]*`?[a-z-]+`?' | head -1)"
  if printf '%s' "$status" | grep -qi 'removed'; then
    fail "the record's status is a state and not removed — a deprecation removes nothing"
  elif [ -n "$status" ]; then
    pass "the record's status is a state and not removed ($status)"
  else
    fail "the record's status is a state and not removed — no Status line was written"
  fi

  # 3. USE IS `unknown`, NOT ZERO. Nothing counts the old path, so a zero
  #    is a claim the record cannot support.
  use_section="$(fixture_markdown_section "$record" 'Use')"
  if [ -z "$use_section" ]; then
    fail "the record says the use is unknown — the Use section is missing"
  elif printf '%s' "$use_section" | grep -qiE '\|[[:space:]]*0[[:space:]]*\|'; then
    fail "the record says the use is unknown — it writes zero for a path nothing counts"
  elif printf '%s' "$use_section" | grep -qi 'unknown'; then
    pass "the record says the use is unknown, not zero"
  else
    fail "the record says the use is unknown, not zero — the Use section states neither"
  fi

  # 4. THE SUNSET DATE IS NOT THE AGENT'S. It belongs to the owner.
  signal="$(fixture_markdown_section "$record" 'Signal')"
  if [ -z "$signal" ]; then
    fail "the record leaves the sunset date to its owner — the Signal section is missing"
  elif printf '%s\n' "$signal" | grep -qiE '^\-[[:space:]]*\*\*Sunset date:\*\*[[:space:]]*[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
    fail "the record leaves the sunset date to its owner — a date was written into the record"
  else
    pass "the record leaves the sunset date to its owner"
  fi

  # 5. THE SIGNAL THE CALLER SEES. An HTTP endpoint's marker is the
  #    `Deprecation` and `Sunset` response headers; a changelog line is not a
  #    signal, because a caller never reads it.
  local routes="src/routes.js"
  if [ ! -f "$routes" ]; then
    fail "the old endpoint carries the deprecation signal — the endpoint file is gone"
  else
    local rbody; rbody="$(cat "$routes")"
    assert_contains "$rbody" 'Deprecation' 'the old endpoint sends the Deprecation header'
    assert_contains "$rbody" 'Sunset' 'the old endpoint sends the Sunset header'
  fi

  # 6. THE OLD PATH STILL WORKS. A deprecation removes nothing; the callers
  #    it was meant to warn have to still be able to call it.
  if [ ! -f src/profile.js ]; then
    fail "the old path is still there — src/profile.js was removed in the change that marked it deprecated"
  elif command -v node >/dev/null 2>&1; then
    local out; out="$(node -e '
      const { legacyProfile } = require("./src/profile");
      console.log(JSON.stringify(legacyProfile({ id: "u1", name: "A", street: "s", city: "c", zip: "z" })));
    ' 2>/dev/null || true)"
    if printf '%s' "$out" | grep -q '"street":"s"'; then
      pass "the old path still returns the old shape"
    else
      fail "the old path still returns the old shape — it returns $out"
    fi
  else
    note "no node runtime — the old path was not called"
  fi

  assert_result
}
