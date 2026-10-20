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

# A tiny HTTP API with a real test suite and a DELIBERATELY BROKEN `npm test`
# (`node --test test/` treats the dir as a module path on modern Node). A skill
# that claims something is verified has to notice its gate does not run.
fixture_node_api() {
  local d="$1"; mkdir -p "$d/src" "$d/test"
  cat > "$d/package.json" <<'EOF'
{ "name": "billing-api", "version": "0.3.0", "scripts": { "test": "node --test test/" } }
EOF
  cat > "$d/src/server.js" <<'EOF'
const routes = new Map();
function route(method, path, handler) { routes.set(`${method} ${path}`, handler); }
async function handle(req) {
  const handler = routes.get(`${req.method} ${req.path}`);
  if (!handler) return { status: 404, body: { error: 'not_found' } };
  return handler(req);
}
module.exports = { route, handle, routes };
EOF
  cat > "$d/src/apikeys.js" <<'EOF'
// Each API key belongs to a tenant and carries a plan tier:
// 'free' | 'pro' | 'enterprise'.
const keys = new Map();
function register(key, tenantId, tier) { keys.set(key, { tenantId, tier }); }
function resolve(authHeader) {
  if (!authHeader?.startsWith('Bearer ')) return null;
  return keys.get(authHeader.slice(7)) ?? null;
}
module.exports = { register, resolve, keys };
EOF
  cat > "$d/test/server.test.js" <<'EOF'
const { test } = require('node:test');
const assert = require('node:assert');
const { route, handle } = require('../src/server');
test('unknown route returns 404', async () => {
  assert.strictEqual((await handle({ method: 'GET', path: '/nope' })).status, 404);
});
test('registered route is dispatched', async () => {
  route('GET', '/ping', () => ({ status: 200, body: { ok: true } }));
  assert.deepStrictEqual((await handle({ method: 'GET', path: '/ping' })).body, { ok: true });
});
EOF
  cat > "$d/README.md" <<'EOF'
# billing-api

Minimal HTTP API for tenant billing. Routes are registered with `route()` and
dispatched by `handle()`. Tests run with `npm test` (node:test).
EOF
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
  local d="$1"
  mkdir -p "$d"/src/{scheduler,legacy,billing,api,orders,sync,import,auth,queue,utils,config} \
           "$d"/docs/{design,product,tickets} \
           "$d"/api "$d"/config

  # Coherent with billing-api: tenants on plan tiers, billed on a schedule.
  echo 'module.exports = { run: (job) => job.handler(); };'                   > "$d/src/scheduler/index.js"
  echo 'module.exports = { legacyInvoice: (t) => ({ tenant: t, lines: [] }) };' > "$d/src/legacy/invoice.js"
  echo 'module.exports = { chargeTenant: (t, cents) => ({ t, cents }) };'     > "$d/src/billing/charge.js"
  echo 'module.exports = { mount: (app) => app };'                            > "$d/src/api/index.js"
  echo 'export const Summary = ({ order }) => order.id;'                      > "$d/src/orders/summary.tsx"
  echo 'module.exports = { pull: async () => [] };'                           > "$d/src/sync/pull.js"
  echo 'module.exports = { importCsv: async (rows) => rows.length };'         > "$d/src/import/csv.js"
  echo 'export const session = { userId: null };'                             > "$d/src/auth/session.ts"
  echo 'module.exports = { consume: async (msg) => msg };'                    > "$d/src/queue/consumer.js"
  echo 'export const cents = (n: number) => Math.round(n * 100);'             > "$d/src/utils/money.ts"
  echo 'export const poolSize = 10;'                                          > "$d/src/config/database.ts"
  echo 'export { poolSize } from "./database";'                               > "$d/src/config/index.ts"

  # The paths a query names in another language, or in a second service, still
  # bind: "the session timeout is in config/session.rb" presupposes that file
  # exists exactly as "src/utils/money.ts" does.
  cat > "$d/src/checkout.js" <<'EOF'
// Order totals for the billing API.
function total(order) {
  return { subtotal: order.subtotal, total: order.subtotal };
}
module.exports = { total };
EOF
  cat > "$d/api/auth.py" <<'EOF'
"""Password reset for the tenant API."""


def request_reset(email):
    """Start a password reset for an account."""
    return {"email": email, "started": True}
EOF
  cat > "$d/api/worker.js" <<'EOF'
// Background worker for the billing API.
module.exports = { start: () => ({ running: true }) };
EOF
  cat > "$d/config/session.rb" <<'EOF'
# Session settings for the billing API.
SESSION_TTL_MINUTES = 30
EOF

  printf '# Notifications design\n\nEmail and webhook delivery for billing events.\n' \
    > "$d/docs/design/notifications.md"
  printf '# Product goals\n\nTenants can self-serve billing without support.\n' \
    > "$d/docs/product/goals.md"
  printf '# Invites\n\nTenant admins invite teammates by email.\n' \
    > "$d/docs/invites.md"

  # A ticket, as the tracker holds it. working-from-a-ticket reads the ticket
  # and writes a capture beside it, so the query that hands over INV-142 needs
  # the source text to be there — the ticket's own acceptance criteria, not a
  # paraphrase of them.
  cat > "$d/docs/tickets/INV-142.md" <<'EOF'
# Ticket: INV-142 — Tenant admins invite teammates by email

**Reported by:** a customer, 2026-10-09
**Component:** tenant administration

## Description

Tenant admins need to invite teammates by email. An invited teammate gets a
link that expires after 7 days. A tenant caps at 25 seats.

## Acceptance criteria

1. "An admin can send an invite from the tenant settings screen."
2. "An invite link stops working 7 days after it was sent." (as written; no
   clock stated, no timezone stated)
3. "A tenant cannot exceed 25 seats." (as written; what happens on the 26th
   invite is not stated)

## Comments

- 2026-10-10, support: "Customers are asking whether an invite can be
  revoked before it is accepted."
EOF

  # A session record, workspace-local, for the skill that reconstructs what a
  # run actually did. It is the only witness of a past run, so a diagnosis has
  # something to read, and the report cites its lines.
  mkdir -p "$d/.agent/sessions"
  cat > "$d/.agent/sessions/2026-10-14-charge-flow.jsonl" <<'EOF'
{"type":"user","line":1,"text":"Refactor src/legacy/invoice.js so it uses the same charge path as the rest of the service."}
{"type":"skill","line":2,"skill":"mapping-the-codebase"}
{"type":"assistant","line":3,"text":"Mapped the legacy invoice path: src/legacy/invoice.js -> src/billing/charge.js -> src/api/index.js."}
{"type":"tool","line":4,"tool":"edit","path":"src/legacy/invoice.js","summary":"replaced the invoice builder with a call to chargeTenant"}
{"type":"tool","line":5,"tool":"bash","cmd":"npm test","summary":"2 passed, 0 failed"}
{"type":"assistant","line":6,"text":"Refactor done, the suite is green. Committing."}
{"type":"tool","line":7,"tool":"bash","cmd":"git commit -am 'refactor legacy invoice path'","summary":"[main 4f1c2ab] refactor legacy invoice path"}
{"type":"user","line":8,"text":"Why did that change also rewrite the tax lookup? I only asked for the charge path."}
EOF

  # The plans. A plan is a DIRECTORY in the current convention
  # (`.sdlc-skills/plans/{{YYYY-MM-DD}}-{{topic}}/`), and its identity is a
  # version computed over its content — never a label it declares about
  # itself. A stub that merely said "Approval: pending" was never a plan a
  # skill could check: the approval has to bind the version the plan really
  # has, and the tasks have to be the files the index lists.
  _fixture_write_plan "$d/.sdlc-skills/plans/2026-09-21-search-rewrite" \
    "search-rewrite" \
    "Search answers the same for every tenant." \
    "A search for one tenant never returns another tenant's rows." \
    "inline" "the search lead" "2026-09-21" \
    "T-001|index-schema|Add the search index to the tenant's tables|todo" \
    "T-002|query-path|Route every search query through the tenant filter|todo"

  _fixture_write_plan "$d/.sdlc-skills/plans/2026-09-28-billing-v2" \
    "billing-v2" \
    "Tenants are billed on the plan tier they bought." \
    "An invoice for a tier is the same on every path that produces one." \
    "inline" "the billing lead" "2026-09-28" \
    "T-001|price-table|Write the price table every invoice reads|todo" \
    "T-002|invoice-cycle|Close the invoice cycle on the plan's anniversary|in progress"

  _fixture_write_plan "$d/.sdlc-skills/plans/2026-10-02-proration" \
    "proration" \
    "A tenant that changes plan mid-cycle is charged the difference." \
    "A mid-cycle plan change produces one proration line on the next invoice." \
    "delegated" "the billing lead" "2026-10-02" \
    "T-001|price-table|Write the price table every invoice reads|done" \
    "T-002|proration|Calculate the proration line for a mid-cycle change|todo" \
    "T-003|rollup|Report proration lines on the invoice export|todo"

  _fixture_write_plan "$d/.sdlc-skills/plans/2026-10-05-multi-tenancy" \
    "multi-tenancy" \
    "Every tenant's rows are isolated from every other tenant's rows." \
    "No endpoint reads, writes or counts another tenant's rows." \
    "inline" "the platform lead" "2026-10-05" \
    "T-001|tenant-column|Add the tenant column to every tenant-scoped table|todo" \
    "T-002|row-filters|Filter every read and write by tenant|todo"

  _fixture_write_plan "$d/.sdlc-skills/plans/2026-10-08-search" \
    "search" \
    "Search answers the same for every tenant." \
    "A search for one tenant never returns another tenant's rows." \
    "delegated" "the search lead" "2026-10-08" \
    "T-001|index-schema|Add the search index to the tenant's tables|done" \
    "T-002|query-path|Route every search query through the tenant filter|in progress"

  _fixture_write_plan "$d/.sdlc-skills/plans/2026-10-12-reporting" \
    "reporting" \
    "A tenant can export its invoices as CSV." \
    "An export of ten thousand rows completes and matches the invoice list." \
    "inline" "the reporting lead" "2026-10-12" \
    "T-001|rollup-job|Nightly rollup of invoices per tenant|todo" \
    "T-002|export|Export the rolled-up invoices as CSV|todo"
}

# A staged plan, in the current format: an index that lists its task files, one
# file per task, and the decision ledger whose approval row binds the plan's
# real version.
#
# The version is computed the way the upstream plan-version.sh computes it:
# `git hash-object` over the index with every task checkbox and state label
# normalized, followed by every task file in index order. Mirrored here so the
# staged approval row names the version the plan actually has — a row naming
# any other version would refuse a run that is correct, which is the one thing
# a fixture must not do.
#
# $1 plan directory (created)   $2 topic   $3 goal   $4 acceptance
# $5 mode (inline|delegated)   $6 decision owner   $7 decision date
# rest: one task per argument, "TASKID|slug|objective|state"
_fixture_write_plan() {
  local dir="$1" topic="$2" goal="$3" acceptance="$4" mode="$5" owner="$6" date="$7"
  shift 7
  local spec id slug objective state n=0
  local -a ids=() slugs=() objectives=() states=() files=()
  for spec in "$@"; do
    id="${spec%%|*}"; spec="${spec#*|}"
    slug="${spec%%|*}"; spec="${spec#*|}"
    objective="${spec%%|*}"; state="${spec##*|}"
    ids+=("$id"); slugs+=("$slug"); objectives+=("$objective"); states+=("$state")
    files+=("$(printf '%02d-%s.md' "$((n + 1))" "$slug")")
    n=$((n + 1))
  done

  mkdir -p "$dir"
  {
    printf '# Plan: %s\n\n' "$topic"
    printf -- '- **Status:** `proposed`\n'
    printf -- '- **Identity:** recorded in the ledger row, never here\n'
    printf -- '- **Predecessor:** none\n'
    printf -- '- **Approval rule:** %s\n' "$owner"
    printf -- '- **Bound inputs:** the approved requirements this plan was written from\n'
    printf -- '- **Selected visual references:** not applicable\n'
    printf -- '- **External decision ledger:** `00-index.ledger.md`\n'
    printf -- '- **External execution ledger:** `00-index.ledger.md`\n'
    printf -- '- **Integration cadence:** `plan end`\n'
    printf -- '- **Out-of-task findings:** `log and report`\n\n'
    printf '**Goal:** %s\n\n' "$goal"
    printf '**Acceptance:** %s\n\n' "$acceptance"
    printf '## Tasks\n\n'
    local i
    for ((i = 0; i < n; i++)); do
      printf -- '- [ ] `%s` — %s   ·   `%s`   ·   `%s`\n' \
        "${ids[i]}" "${objectives[i]}" "${files[i]}" "${states[i]}"
    done
  } > "$dir/00-index.md"

  local i file
  for ((i = 0; i < n; i++)); do
    file="${files[i]}"
    {
      printf '# Task %02d: %s\n\n' "$((i + 1))" "${objectives[i]}"
      printf '**Task ID:** `%s`\n' "${ids[i]}"
      printf '**Objective:** %s\n' "${objectives[i]}"
      printf '**Depends on:** none\n'
      printf '**Files:** `src/%s.js` (edit)\n' "${slugs[i]}"
      printf '**Exclusive ownership/effects:** `src/%s.js`\n' "${slugs[i]}"
      printf '**Context:** `src/server.js`\n'
      printf '**Applicable visual references:** not applicable\n'
      printf '**Suggested tier:** small\n'
      printf '**Implementation disciplines:** `test-driven-development` + `yagni`\n\n'
      printf '## Change\n\n'
      printf '%s.\n\n' "${objectives[i]}"
      printf '**Interface**\n\n'
      printf -- '- **Consumes:** nothing\n'
      printf -- '- **Produces:** `%s`\n\n' "${slugs[i]}"
      printf '## Evaluator\n\n'
      printf '**Evaluator identity/owner:** `%s-gate` — the task gate; this task may not edit it.\n\n' "${ids[i]}"
      printf '```bash\n'
      printf 'npm test -- test/%s.test.js\n' "${slugs[i]}"
      printf '```\n\n'
      printf 'Expected: the gate passes\n'
    } > "$dir/$file"
  done

  # The ledger: one decision row (the approval, carrying the mode) and one
  # execution row per task that has already run. Both bind the version the
  # plan has NOW, computed from the files above.
  local version
  version="$(_fixture_plan_version "$dir" "${files[@]}")"
  # A ledger row's Location is the artifact's path FROM THE PROJECT ROOT, so
  # it is relative; an absolute path would name the throwaway tree a probe
  # happens to run in.
  local root="${dir%/.sdlc-skills/plans/*}"
  local rel="${dir#"$root"/}"
  {
    printf '# Decision ledger — %s\n\n' "$topic"
    printf '| Identity | Section | Location | State | Bound evidence | Updated |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    printf '| %s |  | %s/00-index.md | approved | mode: %s — %s | %s |\n' \
      "$version" "$rel" "$mode" "$owner" "$date"
    for ((i = 0; i < n; i++)); do
      [ "${states[i]}" = "todo" ] && continue
      printf '| %s | %s | %s/%s | %s | attempt 1 — `npm test` passed — %s | %s |\n' \
        "$version" "${ids[i]}" "$rel" "${files[i]}" "${states[i]}" "$owner" "$date"
    done
  } > "$dir/00-index.ledger.md"

  # A delegated plan also has a run ledger, and its first line binds the plan
  # identity the upstream sdd-workspace.sh checks. Its path is the one the
  # upstream v11 layout gives a plan's run records: the evidence directory
  # named after the plan directory.
  if [ "$mode" = "delegated" ]; then
    local root="${dir%/.sdlc-skills/plans/*}"
    local run_dir
    run_dir="$root/.sdlc-skills/evidence/$(basename "$dir")"
    mkdir -p "$run_dir"
    {
      printf '# Subagent-driven run — plan %s, identity %s\n' "$(basename "$dir")" "$version"
      printf '\n'
      printf 'Append only. One row per dispatch, ruling, finding, and admitted finding;\n'
      printf 'task states go to the execution ledger the plan index names.\n'
      printf '\n'
      printf '| When | Kind | Task | Detail |\n'
      printf '| --- | --- | --- | --- |\n'
      for ((i = 0; i < n; i++)); do
        [ "${states[i]}" = "todo" ] && continue
        printf '| %s | dispatch | %s | implementer briefed with the task contract; diff handed to the reviewer |\n' \
          "$date" "${ids[i]}"
      done
    } > "$run_dir/sdd-ledger.md"
  fi
}

# A staged plan's version, computed the way the upstream plan-version.sh
# computes it: the index with every task checkbox and state label normalized,
# then every task file in index order. The task file names are given.
_fixture_plan_version() {
  local dir="$1"; shift
  local state_list='todo|in progress|done|done with concerns|blocked|needs context|cancelled|superseded'
  local file
  {
    sed -E 's/^- \[[ xX]\] (.*)`('"$state_list"')`[[:space:]]*$/- [ ] \1`todo`/' "$dir/00-index.md"
    for file in "$@"; do
      printf '\n=== %s\n' "$file"
      cat "$dir/$file"
    done
  } | tr -d '\r' | git hash-object --stdin | cut -c1-7
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
