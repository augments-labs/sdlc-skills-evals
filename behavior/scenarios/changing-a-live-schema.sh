#!/usr/bin/env bash
# Behavioural scenario: changing-a-live-schema.
#
# Provenance: prospective contract probe
# Clause: skills/implementation/changing-a-live-schema/SKILL.md — "Every phase before contract leaves the store in a shape both the new and the"
# Clause: skills/implementation/changing-a-live-schema/SKILL.md — "This is the point of no return: its rollback is a restore from the retained backup or snapshot, never an application rollback."
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the two clauses above.
#
# The failure this catches: the schema change that is "small". The agent adds
# the column and drops the old one in one migration, because the table has
# three columns. Both code versions run against the store during a roll, and
# the old one reads the old column, so the drop breaks the roll — and the
# rollback it names is an application rollback that can no longer work.
#
# The checks read the record's own structure. The Phases section has to name
# every phase, and the Contract row's rollback has to name a restore rather
# than the previous release: that single cell is the point of no return, and
# a record that puts an application rollback there has mis-placed the only
# irreversible step in the change.
#
# No migration is run here and no store is touched: the fixture is a set of
# SQL files and two code versions, and every check reads files.

scenario_opening() {
  cat <<'EOF'
We are adding a `tenant_ref` column to the orders table and moving the
tenant id onto it. The service reads this store while it deploys, and the
previous release still has to run against it during a roll.

Plan the change the way it has to be phased and leave the record where the
release decision can read it. Do not touch the shared store — the migrations
run under our deploy process, not from here.
EOF
}

scenario_setup() { fixture_schema_store "$1"; }

# The first non-empty cell after the cell whose text is $1. Reads stdin.
_cell() { # $1 cell label
  awk -F'|' -v label="$1" '
    { for (i = 2; i <= NF; i++) {
        v = $i; gsub(/^[ \t]+|[ \t]+$/, "", v);
        if (v == label) {
          for (j = i + 1; j <= NF; j++) {
            w = $j; gsub(/^[ \t]+|[ \t]+$/, "", w);
            if (w != "") { print w; exit }
          }
        }
      } }'
}

scenario_assert() {
  local d="$1" record body phases contract_row nor inputs
  cd "$d" || return 2

  assert_file '.sdlc-skills/designs/*-schema-change-*.md' 'wrote the schema change record'
  record="$ASSERT_MATCH"
  if [ -z "$record" ]; then
    fail "the record sequences the phases — no schema change record was written"
    assert_result
    return
  fi
  body="$(cat "$record")"

  # 1. AN UNFILLED TEMPLATE IS NOT A RECORD.
  assert_not_contains "$body" '\{\{' 'the record has no unfilled template placeholder'

  # 2. EVERY PHASE, IN THE ORDER THE CONTRACT PHASES THEM. A phase the change
  #    does not need is allowed, but it has to say so and say why.
  phases="$(fixture_markdown_section "$record" 'Phases')"
  if [ -z "$phases" ]; then
    fail "the record sequences the phases — the Phases section is missing"
  else
    local p
    for p in 'Expand' 'Dual-write' 'Backfill' 'Switch reads' 'Stop old writes' 'Contract'; do
      if printf '%s' "$phases" | grep -qi "$p"; then
        pass "the Phases section names $p"
      else
        fail "the Phases section names $p — it is missing, and a phase that is not needed has to say so"
      fi
    done
  fi

  # 3. THE CONTRACT'S ROLLBACK IS A RESTORE. The point of no return is the
  #    one step an application rollback cannot undo.
  contract_row="$(printf '%s' "$phases" | grep -iE '^\|[[:space:]]*Contract[[:space:]]*\|' | head -1)"
  if [ -z "$contract_row" ]; then
    fail "the contract phase names a restore as its rollback — the row is missing"
  elif printf '%s' "$contract_row" | grep -qiE 'restore|backup|snapshot'; then
    pass "the contract phase names a restore as its rollback"
  else
    fail "the contract phase names a restore as its rollback — it names an application rollback, which the contract phase cannot have"
  fi

  # 4. THE POINT OF NO RETURN IS RECORDED, WITH A RESTORE PATH AND A STATE.
  nor="$(fixture_markdown_section "$record" 'Point of no return')"
  if [ -z "$nor" ]; then
    fail "the point of no return is recorded — the section is missing"
  else
    if printf '%s\n' "$nor" | grep -qE '^[-*[:space:]]*\*\*Restore path:\*\*[[:space:]]*[^[:space:]]'; then
      pass "the point of no return names a restore path"
    else
      fail "the point of no return names a restore path — the line is empty"
    fi
    if printf '%s\n' "$nor" | grep -qE '^[-*[:space:]]*\*\*Accepted:\*\*[[:space:]]*[^[:space:]]'; then
      pass "the point of no return records who accepted it, or that no row accepted it"
    else
      fail "the point of no return records who accepted it — the line is empty"
    fi
  fi

  # 5. THE INPUTS ARE BOUND. An unbound input is a missing input, never a
  #    value to assume.
  inputs="$(fixture_markdown_section "$record" 'Inputs')"
  if [ -z "$inputs" ]; then
    fail "the record binds its inputs — the Inputs section is missing"
  else
    local tool step
    tool="$(printf '%s\n' "$inputs" | _cell 'Migration tool and conventions')"
    step="$(printf '%s\n' "$inputs" | _cell 'Deploy step that runs migrations')"
    [ -n "$tool" ] && pass "the record names the migration tool and its conventions" \
                   || fail "the record names the migration tool and its conventions — the value is empty"
    [ -n "$step" ] && pass "the record names the deploy step the migrations run at" \
                   || fail "the record names the deploy step the migrations run at — the value is empty"
  fi

  # 6. THE TESTS ARE NAMED. The record's Tests section is what the release
  #    decision reads; an empty one is a missing one.
  local tests rows
  tests="$(fixture_markdown_section "$record" 'Tests')"
  if [ -z "$tests" ]; then
    fail "the record names the tests each phase is built under — the Tests section is missing"
  else
    rows="$(printf '%s\n' "$tests" \
      | grep -oE '[A-Za-z0-9_./-]+\.(test|spec)\.[jt]s(::[A-Za-z0-9_.-]+)?' | wc -l | tr -d ' ')"
    if [ "${rows:-0}" -ge 4 ]; then
      pass "the record names the tests each phase is built under ($rows test paths)"
    else
      fail "the record names the tests each phase is built under — it names $rows test paths"
    fi
  fi

  assert_result
}
