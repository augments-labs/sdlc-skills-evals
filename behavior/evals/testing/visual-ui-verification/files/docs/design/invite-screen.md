# Invite screen — approved design

Version: 1

## Flow

1. Tenant settings opens the team list.
2. "Invite" opens a field for one email address.
3. The invite appears in the pending list with its expiry.

## States

| State | What the operator sees |
| --- | --- |
| pending | the invitee's email and the days left |
| expired | the invitee and "expired", with resend and revoke |
| over seat cap | the seat count and "cap reached"; the invite button is disabled |
| empty team | "No teammates yet" and the invite button |

## Rules

- The seat cap is 25. At the cap the invite button is disabled, not hidden.
- An expired invite can be resent or revoked.
- The pending list is one column on a phone and two columns above 900px.
- Every state is reachable by keyboard, and the button carries its own label
  rather than an icon alone.
