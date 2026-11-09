# Task 02: Calculate the proration line for a mid-cycle change

**Task ID:** `T-002`
**Objective:** Calculate the proration line for a mid-cycle change
**Depends on:** none
**Files:** `src/proration.js` (edit)
**Exclusive ownership/effects:** `src/proration.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Calculate the proration line for a mid-cycle change.

**Interface**

- **Consumes:** nothing
- **Produces:** `proration`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/proration.test.js
```

Expected: the gate passes
