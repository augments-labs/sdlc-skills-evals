# Task 01: Model the invite, its states and the seat-cap invariant

**Task ID:** `T-001`
**Objective:** Model the invite, its states and the seat-cap invariant
**Depends on:** none
**Files:** `src/invite-model.js` (edit)
**Exclusive ownership/effects:** `src/invite-model.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Model the invite, its states and the seat-cap invariant.

**Interface**

- **Consumes:** nothing
- **Produces:** `invite-model`

## Evaluator

**Evaluator identity/owner:** `T-001-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/invite-model.test.js
```

Expected: the gate passes
