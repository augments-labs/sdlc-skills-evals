# Plan: search

- **Status:** `proposed`
- **Identity:** recorded in the ledger row, never here
- **Predecessor:** none
- **Approval rule:** the search lead
- **Bound inputs:** the approved requirements this plan was written from
- **Selected visual references:** not applicable
- **External decision ledger:** `00-index.ledger.md`
- **External execution ledger:** `00-index.ledger.md`
- **Integration cadence:** `plan end`
- **Out-of-task findings:** `log and report`

**Goal:** Search answers the same for every tenant.

**Acceptance:** A search for one tenant never returns another tenant's rows.

## Tasks

- [ ] `T-001` — Add the search index to the tenant's tables   ·   `01-index-schema.md`   ·   `done`
- [ ] `T-002` — Route every search query through the tenant filter   ·   `02-query-path.md`   ·   `in progress`
