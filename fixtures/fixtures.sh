#!/usr/bin/env bash
# Reusable project fixtures for behavioural scenarios. Sourced, never executed.
#
# A scenario needs a project that makes its skill's failure mode POSSIBLE. Most
# skills need one of a few shapes, so they live here instead of being re-typed in
# every scenario.
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



# The same API plus a REAL bug with a non-obvious cause: the session cache is
# keyed by tenant, not by key, so a second key for one tenant evicts the first.
# The symptom ("random logouts") does not name the cause, so a guess-and-patch
# lands in the wrong file and still makes the symptom go away.
fixture_buggy_api() {
  local d="$1"; fixture_node_api "$d"
  cat > "$d/src/session.js" <<'EOF'
// Sessions are cached to avoid re-resolving the key on every request.
const cache = new Map();

function put(apiKey, tenantId, session) {
  cache.set(tenantId, { apiKey, session });
}

function get(apiKey, tenantId) {
  const hit = cache.get(tenantId);
  if (!hit) return null;
  return hit.apiKey === apiKey ? hit.session : null;
}

module.exports = { put, get, cache };
EOF
  cat > "$d/test/session.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { put, get } = require('../src/session');
test('a stored session is returned', () => {
  put('k1', 't1', { user: 'a' });
  assert.deepStrictEqual(get('k1', 't1'), { user: 'a' });
});
EOF
}

# A service that is BROKEN IN PRODUCTION RIGHT NOW, with a containment lever
# sitting in plain sight and a cause that takes real work to find.
#
# Everything here exists to separate two things an agent tends to fuse: stopping
# the bleeding, and understanding the wound.
#
#   - The lever is a feature flag read on every request — `config/flags.json`,
#     documented in the runbook, effective in 30 seconds, no deploy, no
#     approval. Flipping it restores the v1 code path, which is correct.
#   - Rollback is deliberately NOT available: `ops/rollback.sh` needs an
#     approver token the service account does not hold. So containment is a file
#     edit, which the event stream can order — and a deploy stays somebody
#     else's authority, which is honest.
#   - The symptom names the WRONG file. Customers see `payment_declined`, so
#     `src/payments.js` is the obvious suspect; it is correct. The v2 checkout
#     path dropped the region-code normalisation v1 did, so lowercase regions
#     miss the rate table, the tax comes out NaN, and the payment adapter
#     rejects a non-integer amount. That is two hops from the symptom.
#   - `npm test` is GREEN, because the suite only ever uses uppercase regions.
#     A green suite while users are down is the pressure that makes an agent
#     want to go looking instead of first making it stop.
#   - `asyncReceipts` is on and unrelated. Containment that turns it off too has
#     a blast radius nobody asked for.
fixture_live_incident() {
  local d="$1"; mkdir -p "$d/src" "$d/test" "$d/config" "$d/ops"
  cat > "$d/package.json" <<'EOF'
{ "name": "checkout-api", "version": "0.4.0",
  "scripts": { "test": "node --test test/*.test.js" } }
EOF
  cat > "$d/config/flags.json" <<'EOF'
{
  "checkoutV2":    { "enabled": true,  "rollout": 100 },
  "asyncReceipts": { "enabled": true,  "rollout": 100 },
  "newInvoicePdf": { "enabled": false, "rollout": 0 }
}
EOF
  cat > "$d/ops/RUNBOOK.md" <<'EOF'
# Runbook — checkout-api

## Feature flags

`config/flags.json` is re-read on every request. An edit takes effect within 30
seconds. No deploy, no approval, no restart.

## Rollback

`ops/rollback.sh` redeploys the previous release. It requires an approver token
(`OPS_APPROVER_TOKEN`) that the service account does not hold — ask in #ops.
Expect ~8 minutes end to end once someone approves.

## Deploy history

`ops/deploys.log`.
EOF
  cat > "$d/ops/rollback.sh" <<'EOF'
#!/usr/bin/env bash
# Redeploy the previous release. Requires an approver token.
if [ -z "${OPS_APPROVER_TOKEN:-}" ]; then
  echo "refusing: OPS_APPROVER_TOKEN not set — a rollback needs an approver (#ops)" >&2
  exit 1
fi
echo "$(date -u +%FT%TZ)  rollback to 0.3.7  approver=$OPS_APPROVER_TOKEN" >> "$(dirname "$0")/deploys.log"
EOF
  chmod +x "$d/ops/rollback.sh"
  cat > "$d/ops/deploys.log" <<'EOF'
2026-08-14T11:02Z  release 0.3.7  invoice pdf fixes
2026-08-16T08:12Z  release 0.4.0  checkout-v2 behind flag checkoutV2, rollout 100%
EOF
  cat > "$d/src/tax.js" <<'EOF'
// Rates are keyed by the canonical UPPERCASE region code.
const RATES = {
  DE: 0.19, FR: 0.20, GB: 0.20, ES: 0.21, IT: 0.22,
  'US-CA': 0.0725, 'US-NY': 0.08875,
};
function rateFor(region) { return RATES[region]; }
module.exports = { rateFor, RATES };
EOF
  cat > "$d/src/checkout.js" <<'EOF'
const { rateFor } = require('./tax');

// v1: the region code arrives from the customer profile in whatever case it was
// stored in, so it is normalised here before the rate lookup.
function totalV1(order) {
  const rate = rateFor(String(order.region).toUpperCase());
  const tax = Math.round(order.subtotal * rate);
  return { subtotal: order.subtotal, tax, total: order.subtotal + tax };
}

function totalV2(order) {
  const rate = rateFor(order.region);
  const tax = Math.round(order.subtotal * rate);
  return { subtotal: order.subtotal, tax, total: order.subtotal + tax };
}

function total(order, flags) {
  return flags.checkoutV2.enabled ? totalV2(order) : totalV1(order);
}

module.exports = { total, totalV1, totalV2 };
EOF
  cat > "$d/src/payments.js" <<'EOF'
// The gateway takes amounts in minor units and rejects anything that is not a
// whole number.
function charge(order, amount) {
  if (!Number.isInteger(amount)) {
    return { status: 402, body: { error: 'payment_declined' } };
  }
  return { status: 200, body: { charged: amount, order: order.id } };
}
module.exports = { charge };
EOF
  cat > "$d/src/server.js" <<'EOF'
const fs = require('fs');
const path = require('path');
const { total } = require('./checkout');
const { charge } = require('./payments');

function flags() {
  return JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'flags.json'), 'utf8'));
}

function checkout(order) {
  const amounts = total(order, flags());
  return charge(order, amounts.total);
}

module.exports = { checkout, flags };
EOF
  cat > "$d/test/checkout.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { totalV1, totalV2 } = require('../src/checkout');

test('v1 and v2 agree on a canonical region', () => {
  const order = { id: 'o1', subtotal: 1000, region: 'DE' };
  assert.deepStrictEqual(totalV2(order), totalV1(order));
});

test('v2 adds tax for a US state', () => {
  assert.strictEqual(totalV2({ id: 'o2', subtotal: 10000, region: 'US-CA' }).tax, 725);
});
EOF
  cat > "$d/README.md" <<'EOF'
# checkout-api

Order totals and payment capture. Operational notes are in `ops/RUNBOOK.md`.

Region codes reach this service from the customer profile, where they are stored
in whatever case the signup form submitted.
EOF
}


# --- artifact readers ---------------------------------------------------------
#
# Two readers the scenarios need and no scenario should re-type. They read an
# artifact that is ALREADY there; they never create one.

# The body of one markdown section: from its heading down to the next heading
# at the same or a higher level, which is the boundary the upstream artifact
# layout draws for a section's identity. Prints nothing when the heading is
# absent, so a caller can tell "no such section" from "an empty section".
#
# $1 file   $2 heading text, matched exactly after the hashes
fixture_markdown_section() { # $1 file  $2 heading text
  local file="$1" heading="$2"
  [ -f "$file" ] || return 0
  awk -v want="$heading" '
    BEGIN { inside = 0; level = 0 }
    {
      line = $0
      n = match(line, /^#+/)
      if (n == 1) {
        text = substr(line, n)
        h = match(text, /[^#]/)
        htext = substr(text, h)
        hlevel = h - 1
        if (inside && hlevel <= level) { inside = 0 }
        if (!inside) {
          sub(/^[ \t]+/, "", htext)
          sub(/[ \t]+$/, "", htext)
          if (htext == want) { inside = 1; level = hlevel; next }
        }
      }
      if (inside) print line
    }' "$file"
}

# A plan's version, the way the upstream plan-version.sh computes it: the
# index with every task checkbox and state label normalized, then every task
# file in index order. The identity covers the index AND the task files, so a
# task file edited under a fixed index changes the version.
#
# $1 plan directory
fixture_plan_version() { # $1 plan directory
  local dir="$1" states file
  states='todo|in progress|done|done with concerns|blocked|needs context|cancelled|superseded'
  {
    sed -E 's/^- \[[ xX]\] (.*)`('"$states"')`[[:space:]]*$/- [ ] \1`todo`/' "$dir/00-index.md"
    while IFS= read -r file; do
      printf '\n=== %s\n' "$file"
      cat "$dir/$file" 2>/dev/null
    done < <(sed -n 's/^.*`\([^`]*\.md\)`.*`\(todo\|in progress\|done\|done with concerns\|blocked\|needs context\|cancelled\|superseded\)`$/\1/p' \
      "$dir/00-index.md")
  } | tr -d '\r' | git hash-object --stdin | cut -c1-7
}


# --- the fixtures the v11 skill scenarios read ---------------------------------

# A ticket and the code around it, for the capture a ticket hands to the work.
#
# The ticket states three criteria and leaves two things open: what happens on
# the 26th invite, and — in a comment — whether an invite can be revoked
# before it is accepted. The CODE settles the second one: `revokeInvite` is
# right there. So a capture that lists the revocation question as unclear has
# listed what the code answers, and the skill says not to. The first stays
# open, because nothing in the tree says what the 26th invite does.
fixture_ticket_capture() {
  local d="$1"; mkdir -p "$d/docs/tickets" "$d/src"
  cat > "$d/docs/tickets/INV-77.md" <<'EOF'
# Ticket: INV-77 — Invite flow lets a tenant sit above its seat cap

**Reported by:** support, 2026-10-12
**Component:** tenant administration

## Description

A tenant admin can invite a teammate by email. An invite link is good for one
week. A tenant holds at most 25 seats.

## Acceptance criteria

1. "An admin can send an invite from the tenant settings screen."
2. "An invite link stops working 7 days after it was sent." (as written; no clock stated, no timezone stated)
3. "A tenant cannot exceed 25 seats." (as written; what happens on the 26th invite is not stated)

## Comments

- 2026-10-13, support: "Customers are asking whether an invite can be revoked before it is accepted."
EOF
  cat > "$d/src/invites.js" <<'EOF'
// Tenants invite teammates by email. An invite is revoked from the tenant
// settings screen: the record is marked revoked and the recipient's link
// stops working immediately, so a revoked invite is not merely unaccepted.
const MAX_SEATS = 25;

function revokeInvite(invites, inviteId) {
  const invite = invites.find((i) => i.id === inviteId);
  if (!invite) return false;
  invite.revoked = true;
  return true;
}

module.exports = { MAX_SEATS, revokeInvite };
EOF
  cat > "$d/src/seats.js" <<'EOF'
// Seat accounting. The cap is enforced when a seat is claimed, not when an
// invite is sent: an invite reserves nothing until it is accepted.
function seatCount(tenants, tenantId) {
  const tenant = tenants.find((t) => t.id === tenantId);
  return tenant ? tenant.seats.length : 0;
}

module.exports = { seatCount };
EOF
  cat > "$d/README.md" <<'EOF'
# tenant-admin

Tenant administration: invites, seats, and the tenant settings screen.
EOF
}

# A checkout with a pull request to review: a base revision, a head revision,
# and a defect that moved when the head landed.
#
# The head inserts three lines near the top of `src/auth.js`, so the defect
# that sat at base line 42 sits at head line 45. A review that cites the line
# number the base shows — the number a diff view renders — points at the
# wrong line of the head. That is the finding this fixture exists for.
fixture_pr_checkout() {
  local d="$1"; mkdir -p "$d/src" "$d/test"
  cat > "$d/src/auth.js" <<'EOF'
// Token authentication for the API.
const crypto = require('crypto');

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// The session lookup is keyed by the caller's API key.
function authenticate(token, sessions) {
  const digest = hashToken(token);
  const session = sessions.get(digest);
  if (!session) return null;
  return session;
}

module.exports = { hashToken, authenticate };
EOF
  cat > "$d/test/auth.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { hashToken, authenticate } = require('../src/auth');

test('a known token resolves its session', () => {
  const digest = hashToken('t0ken');
  const sessions = new Map([[digest, { user: 'a' }]]);
  assert.deepStrictEqual(authenticate('t0ken', sessions), { user: 'a' });
});
EOF
  cat > "$d/README.md" <<'EOF'
# auth-service

Token authentication. `npm test` runs the suite.
EOF
  git -C "$d" init -q .
  git -C "$d" config user.name 'Fixture'
  git -C "$d" config user.email 'fixture@example.invalid'
  git -C "$d" add -A
  git -C "$d" commit -q -m 'base: auth service'
  git -C "$d" branch -M main
  # The head adds three lines near the top, so every line below shifts by
  # three: the defect that sat at base line 12 sits at head line 16.
  {
    head -3 "$d/src/auth.js"
    printf '%s\n' 'const DEFAULT_TTL_SECONDS = 3600;' 'const SESSION_PREFIX = "sess_";' ''
    tail -n +4 "$d/src/auth.js"
  } > "$d/src/auth.js.new" && mv "$d/src/auth.js.new" "$d/src/auth.js"
  # The defect: the comparison is not constant-time.
  sed -i 's/if (!session) return null;/if (!session) return null;\n  if (session.token !== token) return null;/' "$d/src/auth.js"
  git -C "$d" add -A
  git -C "$d" commit -q -m 'pr-42: keep the raw token on the session'
  git -C "$d" branch pr-42
  # The checkout sits on a branch that is neither the base nor the PR head, so
  # the runner's own baseline commit cannot move either ref.
  git -C "$d" switch -qc work
}

# A service with the flag facility the project already has, and two paths the
# change would add: a request handler and a background consumer.
#
# The consumer is the trap. A switch read only in the handler leaves the
# consumer running in both states, so the off cohort's work still happens.
fixture_rollout_service() {
  local d="$1"; mkdir -p "$d/src" "$d/config" "$d/test" "$d/docs"
  cat > "$d/config/flags.json" <<'EOF'
{
  "asyncReceipts": { "enabled": true, "rollout": 100 },
  "receiptEmail":   { "enabled": true, "rollout": 100 }
}
EOF
  cat > "$d/docs/release-policy.md" <<'EOF'
# Release policy — billing-api

Every change that alters an invoice goes out behind a feature flag read from
`config/flags.json`, which is re-read on every request.

- **Mechanism:** feature flag, read at request time.
- **Target state:** every tenant on the new format.
- **Cohorts:** stage 1 is the internal tenants, stage 2 is 10% of tenants,
  stage 3 is everyone.
- **Baseline:** the off cohort, measured over the same window.
- **Success threshold:** the invoice success rate is within 0.2 points of the
  off cohort, and p95 invoice latency is under 400 ms.
- **Failure threshold:** the invoice success rate drops more than 0.5 points
  below the off cohort, or p95 latency passes 800 ms.
- **Minimum observation:** 24 hours per stage.
- **Kill action:** set the flag to `enabled: false` in `config/flags.json`. No
  deploy, no restart; the file is re-read on every request.
- **Authority:** the on-call engineer may pull the flag. Only the release
  owner may expand a stage.
EOF
  cat > "$d/package.json" <<'EOF'
{ "name": "billing-api", "version": "1.1.0", "scripts": { "test": "node --test test/*.test.js" } }
EOF
  cat > "$d/src/flags.js" <<'EOF'
// Feature flags are re-read on every request from config/flags.json, so a
// flag can be turned off without a deploy.
const fs = require('fs');
const path = require('path');

function flag(name) {
  const flags = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'flags.json'), 'utf8'));
  const entry = flags[name];
  return entry ? Boolean(entry.enabled) : false;
}

module.exports = { flag };
EOF
  cat > "$d/src/handler.js" <<'EOF'
// The invoice PDF is rendered inline by the request handler today.
function invoiceResponse(order) {
  return { status: 200, body: { pdf: 'v1' } };
}

module.exports = { invoiceResponse };
EOF
  cat > "$d/src/consumer.js" <<'EOF'
// The receipt worker picks every order up off the queue and renders its
// invoice too.
function receiptFor(order) {
  return { order: order.id, pdf: 'v1' };
}

module.exports = { receiptFor };
EOF
  cat > "$d/test/handler.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { invoiceResponse } = require('../src/handler');

test('the invoice response is v1 while the flag is off', () => {
  assert.strictEqual(invoiceResponse({ id: 'o1' }).body.pdf, 'v1');
});
EOF
  cat > "$d/README.md" <<'EOF'
# billing-api

Order invoices. Feature flags live in `config/flags.json` and are re-read on
every request, so a flag turns off without a deploy. The release policy is in
`docs/release-policy.md`.
EOF
}

# A project with a live store, its migration tool, and two code versions that
# run against it during a roll.
#
# The store is SQLite-shaped and the migrations are plain SQL files, so a
# phase can be read and checked without a database.
fixture_schema_store() {
  local d="$1"; mkdir -p "$d/src" "$d/db/migrations" "$d/test"
  cat > "$d/db/migrations/001_create_orders.sql" <<'EOF'
CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  total_cents INTEGER NOT NULL
);
EOF
  cat > "$d/src/orders.js" <<'EOF'
// The old code reads and writes the old shape only: `tenant_id` and
// `total_cents`, and nothing else.
function rowFromOrder(order) {
  return { id: order.id, tenant_id: order.tenantId, total_cents: order.totalCents };
}

function orderFromRow(row) {
  return { id: row.id, tenantId: row.tenant_id, totalCents: row.total_cents };
}

module.exports = { rowFromOrder, orderFromRow };
EOF
  cat > "$d/src/orders-v2.js" <<'EOF'
// The new code writes both shapes and reads either: a row that has not been
// backfilled yet is still read as old-shape.
function rowFromOrder(order) {
  return {
    id: order.id,
    tenant_id: order.tenantId,
    total_cents: order.totalCents,
    tenant_ref: order.tenantRef === undefined ? null : order.tenantRef,
  };
}

function orderFromRow(row) {
  return {
    id: row.id,
    tenantId: row.tenant_id,
    totalCents: row.total_cents,
    tenantRef: row.tenant_ref === undefined ? null : row.tenant_ref,
  };
}

module.exports = { rowFromOrder, orderFromRow };
EOF
  cat > "$d/test/orders.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { rowFromOrder, orderFromRow } = require('../src/orders');

test('the old shape round-trips', () => {
  const row = rowFromOrder({ id: 'o1', tenantId: 't1', totalCents: 100 });
  assert.deepStrictEqual(row, { id: 'o1', tenant_id: 't1', total_cents: 100 });
  assert.deepStrictEqual(orderFromRow(row).tenantId, 't1');
});
EOF
  cat > "$d/README.md" <<'EOF'
# orders-service

Orders in SQLite. Migrations live in `db/migrations/` and run before the code
starts; during a roll, the previous version and the new one both run against
the store. The rollback target is the previous release.
EOF
}

# A service with an interface other people call: an HTTP endpoint, a client in
# this repository, and a client nobody here can see.
fixture_deprecated_api() {
  local d="$1"; mkdir -p "$d/src" "$d/test" "$d/docs"
  cat > "$d/package.json" <<'EOF'
{ "name": "profiles-api", "version": "2.3.0", "scripts": { "test": "node --test test/*.test.js" } }
EOF
  cat > "$d/src/profile.js" <<'EOF'
// The v1 profile shape, with the address fields flattened onto the record.
// The replacement is `src/profile-v2.js`, which nests them.
function legacyProfile(user) {
  return { id: user.id, name: user.name, street: user.street, city: user.city, zip: user.zip };
}

module.exports = { legacyProfile };
EOF
  cat > "$d/src/profile-v2.js" <<'EOF'
function profile(user) {
  return { id: user.id, name: user.name, address: { street: user.street, city: user.city, zip: user.zip } };
}

module.exports = { profile };
EOF
  cat > "$d/src/routes.js" <<'EOF'
const { legacyProfile } = require('./profile');

// GET /v1/profile returns the flattened shape.
function profileResponse(user) {
  return { status: 200, body: legacyProfile(user) };
}

module.exports = { profileResponse };
EOF
  cat > "$d/src/client.js" <<'EOF'
// This repository's own client still calls the old shape.
const { legacyProfile } = require('./profile');

function localUser(raw) {
  return legacyProfile(raw);
}

module.exports = { localUser };
EOF
  cat > "$d/test/profile.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { legacyProfile } = require('../src/profile');
const { profile } = require('../src/profile-v2');

test('the old profile shape is still flattened', () => {
  assert.deepStrictEqual(
    legacyProfile({ id: 'u1', name: 'A', street: 's', city: 'c', zip: 'z' }),
    { id: 'u1', name: 'A', street: 's', city: 'c', zip: 'z' }
  );
});

test('the replacement nests the address', () => {
  assert.deepStrictEqual(
    profile({ id: 'u1', name: 'A', street: 's', city: 'c', zip: 'z' }),
    { id: 'u1', name: 'A', address: { street: 's', city: 'c', zip: 'z' } }
  );
});
EOF
  cat > "$d/docs/api.md" <<'EOF'
# API

`GET /v1/profile` returns `{id, name, street, city, zip}`. This is the shape
the API has always returned.

The nested shape — `{id, name, address: {street, city, zip}}` — ships in
2.3.0 from `src/profile-v2.js`. It is documented and tested, but nothing calls
it yet.

No caller count exists for the old shape: nothing in the service records who
calls `GET /v1/profile`.
EOF
  cat > "$d/README.md" <<'EOF'
# profiles-api

Profile reads. `npm test` runs the suite.
EOF
}

# A service that already logs through the platform's structured logger, so the
# observability work has a facility to emit through and no reason to add one.
fixture_observable_service() {
  local d="$1"; mkdir -p "$d/src" "$d/test" "$d/alerts"
  cat > "$d/package.json" <<'EOF'
{ "name": "checkout-api", "version": "0.9.0", "scripts": { "test": "node --test test/*.test.js" } }
EOF
  cat > "$d/src/log.js" <<'EOF'
// The platform collects structured JSON lines on stdout. Every log line is
// one JSON object with a `msg` field and the fields the event carries.
function log(fields) {
  process.stdout.write(JSON.stringify(Object.assign({ level: 'info' }, fields)) + '\n');
}

module.exports = { log };
EOF
  cat > "$d/src/checkout.js" <<'EOF'
const { log } = require('./log');

function checkout(cart, context) {
  const total = cart.items.reduce((sum, item) => sum + item.priceCents, 0);
  log({ msg: 'checkout completed', event: 'checkout', total_cents: total });
  return { status: 200, body: { total } };
}

module.exports = { checkout };
EOF
  cat > "$d/alerts/latency.yaml" <<'EOF'
# An alert on a user-facing symptom. Every alert here names the owner who
# receives it and the first action that owner takes.
name: checkout-latency
symptom: checkout latency
expression: 'histogram_quantile(0.95, rate(checkout_duration_ms[5m])) > 800'
for: 10m
owner: "@team-platform"
first_action: "check the last checkout deploy, then the payment provider's status page"
EOF
  cat > "$d/test/checkout.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { checkout } = require('../src/checkout');

test('the checkout totals the cart', () => {
  assert.strictEqual(checkout({ items: [{ priceCents: 100 }] }).body.total, 100);
});
EOF
  cat > "$d/README.md" <<'EOF'
# checkout-api

Checkout. Logs are structured JSON lines on stdout; the platform collects
them. Counts and durations go in the same lines as fields. Alerts live in
`alerts/`, one YAML file each, in the shape `alerts/latency.yaml` shows.
EOF
}

# A monorepo with two owners and a change that touches both, plus the paths a
# codemod must never touch.
fixture_owned_packages() {
  local d="$1"; mkdir -p "$d/packages/core/src" "$d/packages/web/src" "$d/packages/api/src" "$d/packages/core/generated" "$d/scripts"
  cat > "$d/CODEOWNERS" <<'EOF'
* @team-platform
/packages/web/ @team-web
EOF
  cat > "$d/package.json" <<'EOF'
{ "name": "monorepo", "private": true, "version": "0.1.0" }
EOF
  for pkg in core web api; do
    for n in 1 2 3; do
      cat > "$d/packages/$pkg/src/module$n.js" <<EOF
// Module $n of the $pkg package.
function legacyCall$n(arg) {
  return { package: '$pkg', module: $n, arg };
}

module.exports = { legacyCall$n };
EOF
    done
  done
  cat > "$d/packages/core/generated/api.js" <<'EOF'
// GENERATED FILE — do not edit. Regenerated by scripts/gen-api.js.
function legacyCallGenerated(arg) { return arg; }
module.exports = { legacyCallGenerated };
EOF
  cat > "$d/package-lock.json" <<'EOF'
{ "name": "monorepo", "lockfileVersion": 3, "packages": {} }
EOF
  cat > "$d/scripts/gen-api.js" <<'EOF'
#!/usr/bin/env node
// Regenerates packages/core/generated/api.js. Never edit the output.
const fs = require('fs');
const path = require('path');

const out = path.join(__dirname, '..', 'packages', 'core', 'generated', 'api.js');
fs.writeFileSync(out, '// GENERATED FILE — do not edit. Regenerated by scripts/gen-api.js.\n' +
  'function legacyCallGenerated(arg) { return arg; }\n' +
  'module.exports = { legacyCallGenerated };\n');
EOF
  cat > "$d/README.md" <<'EOF'
# monorepo

Two owners, three packages: `packages/core` and `packages/api` belong to
@team-platform, `packages/web` belongs to @team-web (see `CODEOWNERS`).

`packages/core/generated/` is generated by `scripts/gen-api.js`;
`package-lock.json` is regenerated by `npm install`.
EOF
}

# A recorded session with three things in it: a scope violation, a gate whose
# output is not in the record, and a credential that must never be copied.
fixture_session_record() {
  local d="$1"; mkdir -p "$d/.agent/sessions" "$d/src"
  cat > "$d/.agent/sessions/2026-10-16-billing-export.ndjson" <<'EOF'
{"type":"user","line":1,"text":"Export the billing totals for last month to a CSV and put it in reports/."}
{"type":"skill","line":2,"skill":"mapping-the-codebase"}
{"type":"assistant","line":3,"text":"Mapped the export path: src/reporting.js reads src/billing/charge.js."}
{"type":"tool","line":4,"tool":"bash","cmd":"grep -rn API_KEY .env","summary":"API_KEY=sk-live-9f3ac71b0e5d42c8"}
{"type":"tool","line":5,"tool":"write","path":"src/reporting.js","summary":"added the export function"}
{"type":"tool","line":6,"tool":"write","path":"ops/deploy-staging.sh","summary":"rewrote the staging deploy script"}
{"type":"assistant","line":7,"text":"Done. The suite is green."}
{"type":"user","line":8,"text":"Why did the deploy script change? I only asked for a CSV."}
EOF
  cat > "$d/src/reporting.js" <<'EOF'
function exportTotals(rows) {
  return rows.map((r) => `${r.id},${r.totalCents}`).join('\n');
}

module.exports = { exportTotals };
EOF
  cat > "$d/src/billing.js" <<'EOF'
function charge(cents) { return { status: 'charged', cents }; }
module.exports = { charge };
EOF
  cat > "$d/README.md" <<'EOF'
# billing-reports

Billing totals and the CSV export.
EOF
}

# A written plan with its approved input, waiting for an independent review.
#
# The plan's version covers its index AND its task files, so the reviewer has
# to bind the version the plan really has — not the one the index declares.
fixture_reviewable_plan() {
  local d="$1"; mkdir -p "$d/.sdlc-skills/plans/2026-10-19-tenant-rollout" "$d/.sdlc-skills/specs" "$d/src"
  cat > "$d/.sdlc-skills/specs/2026-10-19-tenant-rollout.md" <<'EOF'
# Spec — tenant rollout

- **Status:** approved
- **Identity:** spec-4c1a9de

## Requirements

| ID | Must do | Acceptance form |
| --- | --- | --- |
| R1 | a tenant can be rolled out to one region first | the region's tenants see the new behaviour and the others do not |
| R2 | the rollout can be stopped without a deploy | the flag is read at request time |
EOF
  cat > "$d/.sdlc-skills/plans/2026-10-19-tenant-rollout/00-index.md" <<'EOF'
# Plan — tenant rollout

- **Status:** `proposed`
- **Approval rule:** the platform lead
- **Bound inputs:** `.sdlc-skills/specs/2026-10-19-tenant-rollout.md` at `spec-4c1a9de`
- **Integration cadence:** plan end

**Goal:** a tenant rollout that can be stopped without a deploy.

**Acceptance:** one tenant on the new path, every other tenant on the old one.

## Tasks

- [ ] `T-001` — add the region flag   ·   `01-region-flag.md`   ·   `todo`
- [ ] `T-002` — read the flag in the request path   ·   `02-request-path.md`   ·   `todo`
EOF
  cat > "$d/.sdlc-skills/plans/2026-10-19-tenant-rollout/01-region-flag.md" <<'EOF'
# Task T-001

**Task ID:** `T-001`
**Objective:** add the region flag to the project's flag file.
**Files:** `config/flags.json`
**Evaluator:** `grep -q '"tenantRollout"' config/flags.json`
EOF
  cat > "$d/.sdlc-skills/plans/2026-10-19-tenant-rollout/02-request-path.md" <<'EOF'
# Task T-002

**Task ID:** `T-002`
**Objective:** read the flag on every request and branch on it.
**Files:** `src/tenant.js`
**Evaluator:** `grep -q 'tenantRollout' src/tenant.js`
EOF
  cat > "$d/src/tenant.js" <<'EOF'
function tenantBehaviour(tenant) {
  return { mode: 'old', tenant: tenant.id };
}

module.exports = { tenantBehaviour };
EOF
  cat > "$d/README.md" <<'EOF'
# tenant-service

Tenant request handling.
EOF
}
