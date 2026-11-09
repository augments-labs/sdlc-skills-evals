# Task 02: Filter every read and write by tenant

**Task ID:** `T-002`
**Objective:** Filter every read and write by tenant
**Depends on:** none
**Files:** `src/row-filters.js` (edit)
**Exclusive ownership/effects:** `src/row-filters.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Filter every read and write by tenant.

**Interface**

- **Consumes:** nothing
- **Produces:** `row-filters`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/row-filters.test.js
```

Expected: the gate passes
