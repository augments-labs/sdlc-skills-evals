# Public API

| Endpoint | Consumers |
| --- | --- |
| `GET /v1/invoices` | billing-web, partner-portal, onboarding-service |
| `POST /v1/charges` | billing-web |

`src/billing/charge.js` exports `chargeTenant`, used by this repository and by
the partner portal through the published package.
