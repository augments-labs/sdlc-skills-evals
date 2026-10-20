# Task 02: Create the invite and send the email

**Task ID:** `T-002`
**Objective:** Create the invite and send the email
**Depends on:** none
**Files:** `src/invite-endpoint.js` (edit)
**Exclusive ownership/effects:** `src/invite-endpoint.js`
**Context:** `src/server.js`
**Applicable visual references:** not applicable
**Suggested tier:** small
**Implementation disciplines:** `test-driven-development` + `yagni`

## Change

Create the invite and send the email.

**Interface**

- **Consumes:** nothing
- **Produces:** `invite-endpoint`

## Evaluator

**Evaluator identity/owner:** `T-002-gate` — the task gate; this task may not edit it.

```bash
npm test -- test/invite-endpoint.test.js
```

Expected: the gate passes
