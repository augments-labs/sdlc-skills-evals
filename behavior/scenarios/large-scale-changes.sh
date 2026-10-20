#!/usr/bin/env bash
# Behavioural scenario: large-scale-changes.
#
# Provenance: prospective contract probe
# Clause: skills/maintenance/large-scale-changes/SKILL.md — "Split by the project's ownership file, or by package when there is none."
# Clause: skills/maintenance/large-scale-changes/SKILL.md — "Instead of one shard per directory or per file, make one per owner: a reviewer handed ten shards approves none of them."
# Clause: skills/maintenance/large-scale-changes/SKILL.md — "Write the transformation as one sentence ... List the paths it never touches: generated, vendored, and lockfile paths, each with the tool that regenerates it."
#
# No live failure was recorded for this skill in this lab, so this is a
# prospective probe: it stands on the three clauses above.
#
# The failure this catches: shards per directory. The monorepo has three
# packages and two owners; a shard per package hands @team-platform two
# review requests and @team-web one, when the ownership file says the first
# two packages belong to the same reviewer. The other half of the failure is
# quieter: the sweep takes the generated file with it, and a file nobody may
# edit is now wrong in the repository.
#
# The checks read the manifest and the tree. The generated file is checked by
# its content, the shard count by the rows the manifest carries, and the
# script by running it twice: a codemod that is not idempotent is a codemod
# whose output cannot be regenerated.

scenario_opening() {
  cat <<'EOF'
Rename every `legacyCall` to `currentCall` across the whole monorepo — it
touches both owners' packages, so it cannot be one reviewable change.

Do it with a script that lives in the repository, leave the generated and
lockfile paths alone, and write the shard manifest so the owners can review
their own piece.
EOF
}

scenario_setup() { fixture_owned_packages "$1"; }

scenario_assert() {
  local d="$1" manifest body shards excluded notcovered script rows owners
  cd "$d" || return 2

  # 1. THE SWEEP REACHED EVERY SOURCE FILE, AND LEFT THE GENERATED ONE.
  local stale
  stale="$(grep -rl 'legacyCall' packages/core/src packages/web/src packages/api/src 2>/dev/null | tr '\n' ' ')"
  if [ -z "$stale" ]; then
    pass "the rename reached every package's source"
  else
    fail "the rename reached every package's source — still legacyCall in: $stale"
  fi
  if grep -q 'legacyCallGenerated' packages/core/generated/api.js 2>/dev/null; then
    pass "the generated file was left alone"
  else
    fail "the generated file was left alone — packages/core/generated/api.js was rewritten"
  fi

  # 2. THE MANIFEST.
  assert_file '.sdlc-skills/designs/*-shards.md' 'wrote the shard manifest'
  manifest="$ASSERT_MATCH"
  if [ -z "$manifest" ]; then
    fail "the manifest splits the change per owner — no shard manifest was written"
    assert_result
    return
  fi
  body="$(cat "$manifest")"
  assert_not_contains "$body" '\{\{' 'the manifest has no unfilled template placeholder'

  # 3. ONE SHARD PER OWNER, NOT PER PACKAGE. The ownership file gives two
  #    owners and three packages.
  shards="$(fixture_markdown_section "$manifest" 'Shards')"
  rows="$(printf '%s\n' "$shards" | awk -F'|' '
    { sep = 1; cells = 0; second = ""
      for (i = 2; i <= NF; i++) { v = $i; gsub(/^[ \t]+|[ \t]+$/, "", v); if (v != "" && v !~ /^-+$/) sep = 0; if (v != "") cells++; if (i == 3) second = v }
      if (!sep && cells >= 3 && second != "Owner") n++ }
    END { print n + 0 }')"
  if [ "${rows:-0}" -eq 2 ]; then
    pass "the manifest has one shard per owner (2 rows for 3 packages)"
  else
    fail "the manifest has one shard per owner — it has $rows rows for 3 packages and 2 owners"
  fi
  owners="$(printf '%s\n' "$shards" | grep -oE '@[a-z-]+' | sort -u | tr '\n' ' ')"
  assert_contains "$owners" '@team-platform' 'the shard for the platform owner is named'
  assert_contains "$owners" '@team-web' 'the shard for the web owner is named'

  # 4. THE EXCLUDED PATHS, WITH WHAT REGENERATES THEM.
  excluded="$(fixture_markdown_section "$manifest" 'Excluded paths')"
  if [ -z "$excluded" ]; then
    fail "the manifest lists the excluded paths — the section is missing"
  else
    assert_contains "$excluded" 'packages/core/generated' 'the generated path is listed as excluded'
    assert_contains "$excluded" 'gen-api\.js' 'the manifest names what regenerates the excluded path'
  fi

  # 5. WHAT THE SCRIPT CANNOT SEE.
  notcovered="$(fixture_markdown_section "$manifest" 'Not covered')"
  local nc_content
  nc_content="$(printf '%s\n' "$notcovered" | grep -vE '^[[:space:]]*$' | grep -vE '^[[:space:]]*\|?[[:space:]]*[-|[:space:]]*\|?[[:space:]]*$' | head -1)"
  if [ -z "$nc_content" ]; then
    fail "the manifest says what the script cannot see — the section is empty"
  else
    pass "the manifest says what the script cannot see"
  fi

  # 6. THE SCRIPT, AND ITS IDEMPOTENCE. The manifest names the script's path;
  #    a codemod that changes something on the second run cannot be
  #    regenerated, and a review cannot be trusted that it was.
  script="$(printf '%s\n' "$body" | grep -oE 'scripts/[A-Za-z0-9_./-]+' | head -1)"
  if [ -z "$script" ] || [ ! -f "$script" ]; then
    fail "the script lives in the repository under the project's scripts path — the manifest names '$script' and it is not there"
  else
    pass "the script lives in the repository under the project's scripts path ($script)"
    local before after rc
    before="$(find . -path ./.git -prune -o -type f -print0 2>/dev/null | xargs -0 sha256sum 2>/dev/null | sort | sha256sum)"
    case "$script" in
      *.js) node "$script" >/dev/null 2>&1 ;;
      *) bash "$script" >/dev/null 2>&1 ;;
    esac
    rc=$?
    after="$(find . -path ./.git -prune -o -type f -print0 2>/dev/null | xargs -0 sha256sum 2>/dev/null | sort | sha256sum)"
    if [ "$rc" -ne 0 ]; then
      fail "the script runs against the repository — it exited $rc"
    elif [ "$before" = "$after" ]; then
      pass "the script is idempotent — running it again changed nothing"
    else
      fail "the script is idempotent — running it again changed the tree"
    fi
  fi

  assert_result
}
