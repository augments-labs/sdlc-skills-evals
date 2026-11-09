# Plan: multi-tenancy

- **Status:** `proposed`
- **Identity:** recorded in the ledger row, never here
- **Predecessor:** none
- **Approval rule:** the platform lead
- **Bound inputs:** the approved requirements this plan was written from
- **Selected visual references:** not applicable
- **External decision ledger:** `00-index.ledger.md`
- **External execution ledger:** `00-index.ledger.md`
- **Integration cadence:** `plan end`
- **Out-of-task findings:** `log and report`

**Goal:** Every tenant's rows are isolated from every other tenant's rows.

**Acceptance:** No endpoint reads, writes or counts another tenant's rows.

## Tasks

- [ ] `T-001` — Add the tenant column to every tenant-scoped table   ·   `01-tenant-column.md`   ·   `todo`
- [ ] `T-002` — Filter every read and write by tenant   ·   `02-row-filters.md`   ·   `todo`
