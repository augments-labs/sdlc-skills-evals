# Task 02: Export the rolled-up invoices as CSV

**Task ID:** `T-002`
**Objective:** Export the rolled-up invoices as CSV
**Depends on:** none
**Files:** `src/export.js` (edit)
**Exclusive ownership/effects:** `src/export.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Export the rolled-up invoices as CSV.

**Interface**

- **Consumes:** nothing
- **Produces:** `export`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/export.test.js
```

Expected: the gate passes
