# Product goals: scheduled jobs survive restarts

## Goals

- Outcome: a job that fell due while a worker was restarting runs once after the restart.
- Guardrail: no job runs twice for the same due time; the invoice run is not idempotent.
- Failure criterion: any missed nightly invoice run in a month.
- Decision rule: the platform lead decides; the platform lead is the person asking.
