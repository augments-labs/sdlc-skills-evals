#!/usr/bin/env bash
# Behavioural scenario: adding-observability.
#
# Provenance: prospective contract probe
# Clause: skills/implementation/adding-observability/SKILL.md — "A counter incremented only on failure has no series until the first"
# Clause: skills/implementation/adding-observability/SKILL.md — "Never a user id, request id, raw URL path, email, or error message text."
# Clause: skills/implementation/adding-observability/SKILL.md — "Write each alert on a user-facing symptom ... with an owner and the first action the owner takes."
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the three clauses above.
#
# The failure this catches: instrumentation that answers a question nobody
# asked. A counter that only moves on failure has no series while things are
# fine, so the success rate the alert reads returns nothing, and the alert
# never fires. A signal labelled with the request id or the raw path makes
# one series per value. An alert with no owner and no first action is noise
# the owner silences along with the real ones.
#
# The checks run the instrumented code. The checkout is called once, with a
# request id, an email, and a raw path in hand, and what it writes to stdout
# is read back: the signal has to be there on the SUCCESS path, and the
# values that must never be labelled are looked for by name. Nothing here
# reads what the agent says it instrumented.

scenario_opening() {
  cat <<'EOF'
When checkout stops working for customers we cannot tell whether it is
working, and we cannot tell why not. I want the operators to be able to
answer both questions from what the service already emits.

Use what this project already has — we do not want a new vendor — and put an
alert on the symptom a user feels, with the owner and the first action named.
EOF
}

scenario_setup() { fixture_observable_service "$1"; }

scenario_assert() {
  local d="$1" added out keys alert owner action symptom
  cd "$d" || return 2
  added="$(added_since_baseline "$d")"

  # 1. A SIGNAL ON THE SUCCESS PATH. The call is made once and succeeds; a
  #    counter that only moves on failure emits nothing here.
  if ! command -v node >/dev/null 2>&1; then
    echo "no node runtime to run the instrumented path — inconclusive"; return 2
  fi
  out="$(node -e '
    const { checkout } = require("./src/checkout");
    checkout(
      { items: [{ priceCents: 100 }] },
      { requestId: "req-9f3ac71b", email: "buyer@example.invalid", rawPath: "/checkout/12345" }
    );
  ' 2>/dev/null || true)"
  keys="$(printf '%s\n' "$out" | jq -Rr 'fromjson? | select(type == "object") | [paths(scalars)] | .[] | map(tostring) | join(".")' 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ -z "$keys" ]; then
    fail "the checkout emits a signal through the project's facility — nothing structured was written"
  else
    if printf '%s' "$keys" | grep -qiE 'duration|latency|elapsed|_ms\b|\bms$'; then
      pass "the signal carries the latency where the user feels it"
    else
      fail "the signal carries the latency where the user feels it — the emitted fields are: $keys"
    fi
    if printf '%s' "$keys" | grep -qiE 'outcome|status|result|success|failure|error'; then
      pass "the signal carries the outcome, so a success rate can be computed from it"
    else
      fail "the signal carries the outcome, so a success rate can be computed from it — the emitted fields are: $keys"
    fi
    # 2. NOTHING UNENUMERABLE IS LABELLED. A request id, an email, and a raw
    #    path make one series per value.
    assert_not_contains "$out" 'req-9f3ac71b' 'the signal does not label with the request id'
    assert_not_contains "$out" 'buyer@example\.invalid' 'the signal does not carry the email'
    assert_not_contains "$out" '/checkout/12345' 'the signal does not label with the raw request path'
  fi

  # 3. NO NEW TELEMETRY VENDOR. The project already emits through its own
  #    logger; the change adds no library.
  if grep -qE '"(dependencies|devDependencies)"[[:space:]]*:[[:space:]]*\{[^}]' package.json 2>/dev/null; then
    fail "no telemetry vendor was added — package.json now carries dependencies"
  else
    pass "no telemetry vendor was added"
  fi

  # 4. AN ALERT ON THE SYMPTOM, WITH AN OWNER AND A FIRST ACTION. The
  #    project's alert shape is the one in alerts/latency.yaml.
  alert=""
  for f in alerts/*.yaml alerts/*.yml; do
    [ -f "$f" ] || continue
    case "$f" in alerts/latency.yaml) continue ;; esac
    if grep -qiE 'symptom:|expression:' "$f"; then alert="$f"; break; fi
  done
  if [ -z "$alert" ]; then
    fail "an alert on the user-facing symptom was added — no alert file beside the project's existing one"
  else
    pass "an alert on the user-facing symptom was added ($alert)"
    owner="$(grep -iE '^[[:space:]]*owner[[:space:]]*:' "$alert" | head -1)"
    action="$(grep -iE '^[[:space:]]*first_action[[:space:]]*:' "$alert" | head -1)"
    symptom="$(grep -iE '^[[:space:]]*(symptom|expression)[[:space:]]*:' "$alert" | head -1)"
    if printf '%s' "$owner" | grep -qE ':[[:space:]]*[^[:space:]]'; then
      pass "the alert names its owner"
    else
      fail "the alert names its owner — the owner line is empty"
    fi
    if printf '%s' "$action" | grep -qE ':[[:space:]]*[^[:space:]]'; then
      pass "the alert names the first action the owner takes"
    else
      fail "the alert names the first action the owner takes — the line is empty"
    fi
    if printf '%s' "$symptom" | grep -qiE 'success|latency|duration|rate'; then
      pass "the alert is written on the user-facing symptom, not on a cause"
    else
      fail "the alert is written on the user-facing symptom, not on a cause — it reads: $symptom"
    fi
  fi

  # 5. A TEST FOR THE SIGNAL. The skill builds each signal under a test
  #    that fails when the signal is missing.
  local tests
  tests="$(printf '%s\n' "$added" | grep -E '\.(test|spec)\.[jt]s$|(^|/)test/' \
           | grep -v 'test/checkout\.test\.js' || true)"
  if [ -n "$tests" ]; then
    pass "the signal is built under a test ($(printf '%s' "$tests" | tr '\n' ' '))"
  else
    fail "the signal is built under a test — no test was added"
  fi

  assert_result
}
