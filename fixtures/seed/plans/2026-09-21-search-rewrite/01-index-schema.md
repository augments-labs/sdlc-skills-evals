# Task 01: Add the search index to the tenant's tables

**Task ID:** `T-001`
**Objective:** Add the search index to the tenant's tables
**Depends on:** none
**Files:** `src/index-schema.js` (edit)
**Exclusive ownership/effects:** `src/index-schema.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Add the search index to the tenant's tables.

**Interface**

- **Consumes:** nothing
- **Produces:** `index-schema`

## Evaluator

**Evaluator identity/owner:** `T-001-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/index-schema.test.js
```

Expected: the gate passes
