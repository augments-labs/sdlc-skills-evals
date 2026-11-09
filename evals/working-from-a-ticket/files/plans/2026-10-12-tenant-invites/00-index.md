# Plan: tenant-invites

- **Status:** `proposed`

- **Identity:** recorded in the ledger row, never here

- **Predecessor:** none

- **Approval rule:** the product lead

- **Bound inputs:** the approved requirements this plan was written from

- **Selected visual references:** not applicable

- **External decision ledger:** `00-index.ledger.md`

- **External execution ledger:** `00-index.ledger.md`

- **Integration cadence:** `plan end`

- **Out-of-task findings:** `log and report`


**Goal:** A tenant admin can invite a teammate by email and the seat cap holds.


**Acceptance:** An invited teammate accepts an invite that has not expired, and the tenant never exceeds its seat cap.


## Tasks


- [ ] `T-001` — Model the invite, its states and the seat-cap invariant   ·   `01-invite-model.md`   ·   `done`

- [ ] `T-002` — Create the invite and send the email   ·   `02-invite-endpoint.md`   ·   `todo`

- [ ] `T-003` — Refuse an invite past the seat cap   ·   `03-seat-cap.md`   ·   `todo`
