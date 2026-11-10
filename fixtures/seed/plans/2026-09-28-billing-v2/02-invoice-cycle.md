# Task 02: Close the invoice cycle on the plan's anniversary

**Task ID:** `T-002`
**Objective:** Close the invoice cycle on the plan's anniversary
**Depends on:** none
**Files:** `src/invoice-cycle.js` (edit)
**Exclusive ownership/effects:** `src/invoice-cycle.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Close the invoice cycle on the plan's anniversary.

**Interface**

- **Consumes:** nothing
- **Produces:** `invoice-cycle`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/invoice-cycle.test.js
```

Expected: the gate passes
