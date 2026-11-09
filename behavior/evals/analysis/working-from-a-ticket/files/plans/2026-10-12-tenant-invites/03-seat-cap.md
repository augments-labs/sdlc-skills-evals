# Task 03: Refuse an invite past the seat cap

**Task ID:** `T-003`
**Objective:** Refuse an invite past the seat cap
**Depends on:** none
**Files:** `src/seat-cap.js` (edit)
**Exclusive ownership/effects:** `src/seat-cap.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Refuse an invite past the seat cap.

**Interface**

- **Consumes:** nothing
- **Produces:** `seat-cap`

## Evaluator

**Evaluator identity/owner:** `T-003-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/seat-cap.test.js
```

Expected: the gate passes
