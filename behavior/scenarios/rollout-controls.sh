#!/usr/bin/env bash
# Behavioural scenario: rollout-controls.
#
# Provenance: prospective contract probe
# Clause: skills/implementation/rollout-controls/SKILL.md — "List every path the change adds: request handler, background job, event"
# Clause: skills/implementation/rollout-controls/SKILL.md — "Make turning it off change behaviour without a deploy: read the switch at runtime, never as a build-time constant."
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the two clauses above.
#
# The failure this catches: a switch in name only. The agent adds the flag,
# reads it in the request handler, and writes a record that says the change
# is behind a flag — while the receipt consumer, which the same change also
# touches, still renders every invoice the new way. The off cohort's work
# still happens, so the rollout compares the new behaviour against itself.
#
# The checks therefore run the code. The flag file is flipped, both paths are
# called, and both have to move; and with the file as the run left it, both
# have to be exactly the prior behaviour. A record that claims two guarded
# paths while the consumer is unguarded fails on the code, not on its prose.
#
# The record's own checks are structural: the template's headings, the
# sections the template says are never empty, and no unfilled placeholder.
# Nothing here reads what the agent says about the rollout.

scenario_opening() {
  cat <<'EOF'
We are changing how invoices are rendered. The new PDF format has to go out
behind a flag, staged the way our release policy says — read
`docs/release-policy.md` and follow it.

Build it so I can turn it off without a deploy, and leave the record of the
rollout where the release decision can read it.
EOF
}

scenario_setup() { fixture_rollout_service "$1"; }

scenario_assert() {
  local d="$1" record body guarded switch_section flags_backup
  cd "$d" || return 2

  assert_file '.sdlc-skills/designs/*-rollout.md' 'wrote the rollout record'
  record="$ASSERT_MATCH"
  if [ -z "$record" ]; then
    fail "the record names the guarded paths — no rollout record was written"
    assert_result
    return
  fi
  body="$(cat "$record")"

  # 1. AN UNFILLED TEMPLATE IS NOT A RECORD.
  assert_not_contains "$body" '\{\{' 'the record has no unfilled template placeholder'

  # 2. THE GUARDED PATHS. Both the request handler and the background
  #    consumer are paths this change touches; a record that names one of
  #    them guards one of them.
  guarded="$(fixture_markdown_section "$record" 'Guarded paths')"
  if [ -z "$guarded" ]; then
    fail "the record names the guarded paths — the section is missing"
  else
    assert_contains "$guarded" 'src/handler\.js' 'the request handler is listed as a guarded path'
    assert_contains "$guarded" 'src/consumer\.js' 'the background consumer is listed as a guarded path'
  fi

  # 3. THE SWITCH, WITH AN OFF ACTION AND NO PLACEHOLDER.
  switch_section="$(fixture_markdown_section "$record" 'Switch')"
  if [ -z "$switch_section" ]; then
    fail "the record names the switch — the section is missing"
  else
    if printf '%s' "$switch_section" | grep -qE '^\|[[:space:]]*Off action[[:space:]]*\|[[:space:]]*[^|[:space:]]'; then
      pass "the record states the exact off action"
    else
      fail "the record states the exact off action — the row is empty"
    fi
    if printf '%s' "$switch_section" | grep -qE '^\|[[:space:]]*Default[[:space:]]*\|[[:space:]]*(off|false|disabled)'; then
      pass "the record states the switch defaults off"
    else
      fail "the record states the switch defaults off — the row does not say off"
    fi
  fi

  # 4. THE SIGNALS SECTION EXISTS. The template says an empty section means
  #    the thing was not built, so its absence is not a quiet pass.
  if [ -n "$(fixture_markdown_section "$record" 'Signals and baseline')" ]; then
    pass "the record carries the signals and the baseline"
  else
    fail "the record carries the signals and the baseline — the section is missing"
  fi

  # 5. THE CODE. Both paths, both states. The flag file is the project's own
  #    facility; every flag in it is turned on for the probe and restored
  #    afterwards, so the check does not have to know the flag's name.
  if ! command -v node >/dev/null 2>&1; then
    echo "no node runtime to run the paths — inconclusive"; return 2
  fi
  if [ ! -f config/flags.json ] || [ ! -f src/handler.js ] || [ ! -f src/consumer.js ]; then
    fail "the switch is read on every path the change adds — the project's flag file or a path is missing"
    assert_result
    return
  fi
  flags_backup="$(cat config/flags.json)"
  local probe_on probe_off
  probe_off="$(node -e '
    const { invoiceResponse } = require("./src/handler");
    const { receiptFor } = require("./src/consumer");
    console.log("handler " + JSON.stringify(invoiceResponse({ id: "o1" })));
    console.log("consumer " + JSON.stringify(receiptFor({ id: "o1" })));
  ' 2>/dev/null || true)"
  node -e '
    const fs = require("fs");
    const p = "config/flags.json";
    const flags = JSON.parse(fs.readFileSync(p, "utf8"));
    for (const k of Object.keys(flags)) flags[k].enabled = true;
    fs.writeFileSync(p, JSON.stringify(flags, null, 2) + "\n");
  ' 2>/dev/null || true
  probe_on="$(node -e '
    const { invoiceResponse } = require("./src/handler");
    const { receiptFor } = require("./src/consumer");
    console.log("handler " + JSON.stringify(invoiceResponse({ id: "o1" })));
    console.log("consumer " + JSON.stringify(receiptFor({ id: "o1" })));
  ' 2>/dev/null || true)"
  printf '%s\n' "$flags_backup" > config/flags.json

  if [ -z "$probe_off" ] || [ -z "$probe_on" ]; then
    fail "the switch is read on every path the change adds — the paths do not load"
  else
    local off_handler off_consumer on_handler on_consumer
    off_handler="$(printf '%s\n' "$probe_off" | sed -n 's/^handler //p')"
    off_consumer="$(printf '%s\n' "$probe_off" | sed -n 's/^consumer //p')"
    on_handler="$(printf '%s\n' "$probe_on" | sed -n 's/^handler //p')"
    on_consumer="$(printf '%s\n' "$probe_on" | sed -n 's/^consumer //p')"

    if [ "$on_handler" != "$off_handler" ]; then
      pass "the request handler is behind the switch (off: $off_handler; on: $on_handler)"
    else
      fail "the request handler is behind the switch — turning it on changed nothing ($off_handler)"
    fi
    if [ "$on_consumer" != "$off_consumer" ]; then
      pass "the background consumer is behind the switch too (off: $off_consumer; on: $on_consumer)"
    else
      fail "the background consumer is behind the switch too — turning it on changed nothing ($off_consumer); a switch on the request path alone leaves this path running in both states"
    fi
    if printf '%s\n%s' "$off_handler" "$off_consumer" | grep -q 'v1'; then
      pass "off still means before — both paths keep the prior behaviour"
    else
      fail "off still means before — the prior behaviour is gone (handler $off_handler, consumer $off_consumer)"
    fi
  fi

  assert_result
}
