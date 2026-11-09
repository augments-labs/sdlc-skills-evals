# Runbook — billing-api

## Feature flags

`config/flags.json` is re-read on every request. An edit takes effect within
30 seconds. No deploy, no approval, no restart.

## Rollback

Rolling back redeploys the previous release. It needs an approver token
(`OPS_APPROVER_TOKEN`) that the service account does not hold — ask in #ops.
Expect ~8 minutes end to end once someone approves.
