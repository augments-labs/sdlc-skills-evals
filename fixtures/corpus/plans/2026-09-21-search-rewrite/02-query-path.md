# Task 02: Route every search query through the tenant filter

**Task ID:** `T-002`
**Objective:** Route every search query through the tenant filter
**Depends on:** none
**Files:** `src/query-path.js` (edit)
**Exclusive ownership/effects:** `src/query-path.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Route every search query through the tenant filter.

**Interface**

- **Consumes:** nothing
- **Produces:** `query-path`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/query-path.test.js
```

Expected: the gate passes
