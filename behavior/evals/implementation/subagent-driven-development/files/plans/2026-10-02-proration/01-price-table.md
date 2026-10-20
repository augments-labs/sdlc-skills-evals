# Task 01: Write the price table every invoice reads

**Task ID:** `T-001`
**Objective:** Write the price table every invoice reads
**Depends on:** none
**Files:** `src/price-table.js` (edit)
**Exclusive ownership/effects:** `src/price-table.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Write the price table every invoice reads.

**Interface**

- **Consumes:** nothing
- **Produces:** `price-table`

## Evaluator

**Evaluator identity/owner:** `T-001-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/price-table.test.js
```

Expected: the gate passes
