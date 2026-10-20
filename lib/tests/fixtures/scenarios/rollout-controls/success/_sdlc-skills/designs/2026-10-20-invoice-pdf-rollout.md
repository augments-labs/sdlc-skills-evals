# Rollout record — invoice-pdf-v2

- **Change:** task/invoice-pdf-v2
- **Predecessor:** none
- **Inputs:** `docs/release-policy.md`, the project's release policy
- **Owner:** the release owner named by the policy
- **Status:** `terms from policy`
- **Decision ledger:** `.sdlc-skills/designs/2026-10-20-invoice-pdf-v2-rollout.ledger.md`

## Policy

- **Source:** `docs/release-policy.md`, the project's release policy
- **Mechanism:** feature flag, read at request time
- **Target state:** every tenant on the new invoice format
- **Authority:** the on-call engineer may pull the flag; only the release
  owner may expand a stage

## Switch

| | |
| --- | --- |
| Name | newInvoicePdf |
| Facility | `config/flags.json`, re-read on every request through `src/flags.js` |
| Default | off |
| Off action | set `newInvoicePdf.enabled` to `false` in `config/flags.json`; the file is re-read on the next request, so no deploy and no restart |
| Off-state test | `test/handler.test.js` — the invoice response is v1 while the flag is off |
| On-state test | `test/handler.test.js` — the invoice response is v2 while the flag is on |

## Guarded paths

| Path | Kind | Where the switch is read | Side effect it precedes |
| --- | --- | --- | --- |
| `src/handler.js` | request handler | `src/handler.js:3` | rendering the invoice in the new format |
| `src/consumer.js` | background consumer | `src/consumer.js:3` | rendering the receipt's invoice in the new format |

## Signals and baseline

| Signal | Measures | Threshold it serves | Carries switch state | Test |
| --- | --- | --- | --- | --- |
| invoice_success_rate | correctness | the success-rate threshold the policy names | `newInvoicePdf` label | `test/handler.test.js` |
| invoice_duration_ms | latency | the latency threshold the policy names | `newInvoicePdf` label | `test/handler.test.js` |

- **Emitted through:** the project's existing structured log lines
- **Baseline source:** the off cohort

## Stages, thresholds, and kill action

| Stage | Cohort | Minimum observation | Success threshold | Failure threshold |
| --- | --- | --- | --- | --- |
| 1 | internal tenants | 24 hours | the policy's success and latency thresholds | the policy's failure thresholds |
| 2 | 10% of tenants | 24 hours | the policy's success and latency thresholds | the policy's failure thresholds |
| 3 | everyone | 24 hours | the policy's success and latency thresholds | the policy's failure thresholds |

- **Kill or rollback action:** set `newInvoicePdf.enabled` to `false` in
  `config/flags.json`
- **Who may pull it:** the on-call engineer

## Removal

- **Owner:** the release owner
- **Condition:** full rollout observed for the policy's minimum period, and the
  prior path removed

## Not built

Nothing: the policy asks for a flag, the guarded paths, the signals the
thresholds read, and the removal follow-up, and all four are here.

## Next action

The release decision, through `release-readiness`, with this record.
