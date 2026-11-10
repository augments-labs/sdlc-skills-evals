# Task 01: Nightly rollup of invoices per tenant

**Task ID:** `T-001`
**Objective:** Nightly rollup of invoices per tenant
**Depends on:** none
**Files:** `src/rollup-job.js` (edit)
**Exclusive ownership/effects:** `src/rollup-job.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Nightly rollup of invoices per tenant.

**Interface**

- **Consumes:** nothing
- **Produces:** `rollup-job`

## Evaluator

**Evaluator identity/owner:** `T-001-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/rollup-job.test.js
```

Expected: the gate passes
