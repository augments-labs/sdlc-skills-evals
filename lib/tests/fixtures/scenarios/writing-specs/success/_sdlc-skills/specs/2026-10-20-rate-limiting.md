# Spec — per-API-key rate limiting

- **Status:** proposed
- **Approval rule:** the maintainer

## Requirements

| ID | Must do | Acceptance form | Artifact today, or gate + owner |
| --- | --- | --- | --- |
| R1 | a client can tell how much budget it has left | the response carries the remaining allowance | `test/ratelimit.test.js` — the allowance the client reads |
| R2 | a request over the ceiling is refused with a retry hint | the response is 429 and carries the retry hint | `test/ratelimit.test.js` — the 429 and its hint |
| R3 | the ceilings are free is 1,000, pro is 50,000, enterprise is unlimited | each tier's ceiling is what the spec says | `test/ratelimit.test.js` — the per-tier ceiling |

## Verified by

- The allowance a client reads: `ratelimit.test.js`
- The 429 and its retry hint: `ratelimit.test.js`
- The per-tier ceiling: `ratelimit.test.js`
