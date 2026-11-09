# Plan: reporting

- **Status:** `proposed`
- **Identity:** recorded in the ledger row, never here
- **Predecessor:** none
- **Approval rule:** the reporting lead
- **Bound inputs:** the approved requirements this plan was written from
- **Selected visual references:** not applicable
- **External decision ledger:** `00-index.ledger.md`
- **External execution ledger:** `00-index.ledger.md`
- **Integration cadence:** `plan end`
- **Out-of-task findings:** `log and report`

**Goal:** A tenant can export its invoices as CSV.

**Acceptance:** An export of ten thousand rows completes and matches the invoice list.

## Tasks

- [ ] `T-001` — Nightly rollup of invoices per tenant   ·   `01-rollup-job.md`   ·   `todo`
- [ ] `T-002` — Export the rolled-up invoices as CSV   ·   `02-export.md`   ·   `todo`
