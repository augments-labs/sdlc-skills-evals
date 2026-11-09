#!/usr/bin/env bash
# Reusable project fixtures the corpus runners stage. Sourced, never executed.
#
# A query needs a project that makes its skill's failure mode POSSIBLE. Most
# skills need one of a few shapes, so they live here instead of being re-typed in
# every query.
#
# Each is small on purpose: an agent that must read 2,000 lines before it can act
# spends the run reading. These give it enough to be wrong in an interesting way,
# and nothing more.

# The tracked corpus root: the material the seeded trees are built from.
#
# It is a committed root of its own, and not the project's own `.sdlc-skills/`
# directory: the repository ignores that one, so a fixture placed there would
# be present in the working tree and absent from the commit — which is exactly
# the failure this root exists to end. A plan fixture is a REPRESENTATION of a
# plan, staged where a plan lives; it is not the lab's own plan.
fixture_corpus_root() {
  local src="${BASH_SOURCE[0]}"
  ( cd "$(dirname "$src")/corpus" && pwd )
}


# A tiny HTTP API with a real test suite and a DELIBERATELY BROKEN `npm test`
# (`node --test test/` treats the dir as a module path on modern Node). A skill
# that claims something is verified has to notice its gate does not run.
#
# The material comes from the tracked corpus root, so the tree a run is given
# is the tree the repository holds: nothing here is written by a script whose
# output the repository does not carry.
fixture_node_api() {
  local d="$1" root
  root="$(fixture_corpus_root)"
  mkdir -p "$d/src" "$d/test"
  cp "$root/project/package.json" "$root/project/README.md" "$d/"
  cp "$root/project/src/server.js" "$root/project/src/apikeys.js" "$d/src/"
  cp "$root/project/test/server.test.js" "$d/test/"
}

# The paths activation queries NAME, and nothing more. Separate from the two
# fixtures above on purpose: a behavioural arm reads the code it is given, so
# padding it costs every run: an activation probe only has to find that the path
# it names is really there.
#
# Why it has to exist at all is the same reason the bare workdir does not work.
# A query is only realistic if its subject is: "redesign src/legacy/" against a
# tree with no src/legacy/ gets the correct answer that there is no such
# directory, and the run routes nowhere. That scores as a trigger miss with
# nothing wrong with the description — the failure this file exists to prevent,
# one level down. Presupposing verbs are the trap; "add src/utils/money.ts"
# reads fine either way, "refactor" and "execute" do not.
#
# So these are stubs, not implementations: enough that the named thing is real,
# never enough to be worth reading. Add one here when a query names a new path.
#
# A query can name an area in prose rather than by path — "the payments area",
# "the reporting service" — and that binds just as hard when the verb
# presupposes it. Nothing checks either half now: a path a query names may
# simply not exist here, and matching area nouns in natural language
# false-positives too badly to be worth automating at all. Both stay a review
# question, and the prose half was always the harder one. Ask it
# where the SKILL ITSELF has to read existing code — mapping-the-codebase orienting in an
# area, refactor-architecture grounding a proposal in the current structure. A
# query that only DESIGNS something ("model the entities for the permissions
# system") presupposes nothing and needs no fixture.
#
# The path half is not a review question any more: `lib/tests/corpora.sh`
# extracts every path a query names and checks it against the tree this
# function stages, so a query naming a path nothing stages is a red cell
# rather than a silently mis-scored run.
fixture_activation_paths() {
  local d="$1" root
  root="$(fixture_corpus_root)"
  mkdir -p "$d/.sdlc-skills/plans" "$d/.agent/sessions" "$d/docs/tickets"

  # the project the queries name
  for f in src/scheduler/index.js src/legacy/invoice.js src/billing/charge.js \
           src/api/index.js src/orders/summary.tsx src/sync/pull.js \
           src/import/csv.js src/auth/session.ts src/queue/consumer.js \
           src/utils/money.ts src/config/database.ts src/config/index.ts \
           src/checkout.js api/auth.py api/worker.js config/session.rb \
           docs/design/notifications.md docs/product/goals.md docs/invites.md; do
    mkdir -p "$d/$(dirname "$f")"
    cp "$root/project/$f" "$d/$f"
  done

  # the ticket, as the tracker holds it: working-from-a-ticket reads it and
  # writes a capture beside it, so the query that hands over INV-142 needs the
  # source text to be there.
  cp "$root/project/docs/tickets/INV-142.md" "$d/docs/tickets/INV-142.md"

  # a session record, workspace-local, for the skill that reconstructs what a
  # run actually did. It is the only witness of a past run, so a diagnosis has
  # something to read, and the report cites its lines.
  cp "$root/project/.agent/sessions/2026-10-14-charge-flow.ndjson" \
     "$d/.agent/sessions/2026-10-14-charge-flow.ndjson"

  # the plans. A plan is a directory in the current convention, and its
  # identity is a version computed over its content — never a label it
  # declares about itself — so the approval row in each ledger binds the
  # version the plan really has.
  for p in "$root"/plans/*/; do
    name="$(basename "$p")"
    mkdir -p "$d/.sdlc-skills/plans/$name"
    cp "$p"* "$d/.sdlc-skills/plans/$name/"
  done

  # a delegated plan's run ledger, which lives under the evidence directory
  # named after the plan directory.
  if [ -d "$root/evidence" ]; then
    for e in "$root"/evidence/*/; do
      name="$(basename "$e")"
      mkdir -p "$d/.sdlc-skills/evidence/$name"
      cp "$e"* "$d/.sdlc-skills/evidence/$name/"
    done
  fi
}
