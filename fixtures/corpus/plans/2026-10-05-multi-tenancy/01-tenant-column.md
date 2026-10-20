# Task 01: Add the tenant column to every tenant-scoped table

**Task ID:** `T-001`
**Objective:** Add the tenant column to every tenant-scoped table
**Depends on:** none
**Files:** `src/tenant-column.js` (edit)
**Exclusive ownership/effects:** `src/tenant-column.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Add the tenant column to every tenant-scoped table.

**Interface**

- **Consumes:** nothing
- **Produces:** `tenant-column`

## Evaluator

**Evaluator identity/owner:** `T-001-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/tenant-column.test.js
```

Expected: the gate passes
