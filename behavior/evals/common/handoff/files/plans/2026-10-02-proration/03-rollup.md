# Task 03: Report proration lines on the invoice export

**Task ID:** `T-003`
**Objective:** Report proration lines on the invoice export
**Depends on:** none
**Files:** `src/rollup.js` (edit)
**Exclusive ownership/effects:** `src/rollup.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Report proration lines on the invoice export.

**Interface**

- **Consumes:** nothing
- **Produces:** `rollup`

## Evaluator

**Evaluator identity/owner:** `T-003-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/rollup.test.js
```

Expected: the gate passes
