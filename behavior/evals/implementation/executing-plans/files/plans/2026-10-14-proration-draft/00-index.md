# Plan: proration

- **Status:** `proposed`
- **Identity:** recorded in the ledger row, never here
- **Predecessor:** none
- **Approval rule:** the billing lead
- **Bound inputs:** the approved requirements this plan was written from
- **Selected visual references:** not applicable
- **External decision ledger:** `00-index.ledger.md`
- **External execution ledger:** `00-index.ledger.md`
- **Integration cadence:** `plan end`
- **Out-of-task findings:** `log and report`

**Goal:** A tenant that changes plan mid-cycle is charged the difference.

**Acceptance:** A mid-cycle plan change produces one proration line on the next invoice.

## Tasks

- [ ] `T-001` — Write the price table every invoice reads   ·   `01-price-table.md`   ·   `done`
- [ ] `T-002` — Calculate the proration line for a mid-cycle change   ·   `02-proration.md`   ·   `todo`
- [ ] `T-003` — Report proration lines on the invoice export   ·   `03-rollup.md`   ·   `todo`
