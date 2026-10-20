# Schema change record — tenant-ref

- **Change:** task/tenant-ref, phase expand
- **Predecessor:** none
- **Inputs:** no data-model section — the tenant semantics are unchanged; only a
  new reference column is added. The task that asked for it.
- **Owner:** the data owner for the contract phase; the deploy owner for order
- **Status:** `expanded`
- **Decision ledger:** `.sdlc-skills/designs/2026-10-20-tenant-ref-schema-change-expand.ledger.md`

## Inputs

| Input | Value | Source |
| --- | --- | --- |
| Migration tool and conventions | plain SQL files in `db/migrations/`, numbered in the order they run | `db/migrations/001_create_orders.sql` |
| Deploy step that runs migrations | before the code starts | the deploy model in `README.md` |
| Code versions live during a roll | two — the previous release and the new one | the deploy model |
| Rollback target | release 1.4.0, which reads and writes `tenant_id` alone | the release record |
| Store engine and version | SQLite 3.45 | the shared environments |
| Affected data | about 400k order rows, 30 writes a second, one replica | the operations dashboard |

## Phases

| Phase | Migration or code change | Order | Gate to advance | Rollback |
| --- | --- | --- | --- | --- |
| Expand | add the nullable `tenant_ref` column to `orders` | migration before code | the previous version's suite passes against the expanded schema | revert the code; the expansion stays and is harmless |
| Dual-write and tolerant reads | the new code writes both shapes and reads either | code only | the tests in Tests | the previous version, which reads and writes the old shape alone |
| Backfill | a batched job that fills `tenant_ref` from `tenant_id` | job under the deploy process | remaining rows zero and the verification passed | stop the job; the rows already written stay valid |
| Switch reads | the read path prefers `tenant_ref` and falls back to `tenant_id` | code only | reads are correct on backfilled and unbackfilled rows | the previous change, which reads either shape |
| Stop old writes | the write path stops writing `tenant_id` | code only | no old-shape writes observed for 24 hours | the previous change, which still writes both shapes |
| Contract | drop `tenant_id` from `orders` | code before migration | the conditions in Point of no return | restore from the retained backup, with its recovery time; an application rollback to 1.4.0 ends here |

## Backfill

- **Batch key and size:** `id`, 1000 rows a batch
- **Cursor:** `backfill_cursor` in the `backfill_runs` table
- **Throttle:** pauses when the replica lag passes two seconds
- **Progress:** remaining rows, rate, and errors are read from the job's own log
- **Verification:** a count comparing the two shapes, compared before and after

## Lock and rewrite evidence

| Operation | Engine documentation says | Measured on | Duration, lock held, rewritten |
| --- | --- | --- | --- |
| add a nullable column | SQLite adds a column without rewriting the table | none: unverified | unverified |

## Tests

New behaviour, each red before its code existed:

| Test | Path and name | RED seen on | GREEN seen on |
| --- | --- | --- | --- |
| Migration applies to the previous schema version | `test/migration.test.js` — the migration applies to the previous schema version | 2026-10-20 | 2026-10-20 |
| Backfill run twice changes nothing the second time | `test/backfill.test.js` — a second run changes nothing | 2026-10-20 | 2026-10-20 |
| Backfill resumes after interruption | `test/backfill.test.js` — an interrupted run resumes to the same end state | 2026-10-20 | 2026-10-20 |
| Reads handle a row not yet backfilled | `test/orders-v2.test.js` — a row with no `tenant_ref` reads as old-shape | 2026-10-20 | 2026-10-20 |

Preserved behaviour, under the preserved-behaviour cycle:

| Test | Suite and version it ran | Accepted as covering the contract by | Seen green on | Deliberate red: divergence and revision | Green again on |
| --- | --- | --- | --- | --- | --- |
| Previous code version passes against the expanded schema | `test/orders.test.js`, the previous release's suite | the task that asked for the change | 2026-10-20 | a required column with no default, at 2026-10-20 | 2026-10-20 |

## Point of no return

- **Phase:** contract, dropping `tenant_id`
- **No live version reads the old shape:** not reached — the expand phase is the
  first one, and no live version reads `tenant_ref` yet
- **Rollback target does not read it:** release 1.4.0 reads `tenant_id`, so the
  contract cannot ship while that is the rollback target
- **Verification re-run after old writes stopped:** not reached
- **Retention allows:** the orders table keeps 90 days of history
- **Restore path:** the nightly snapshot of the orders table, 4 hours to
  restore
- **Accepted:** no row — the contract has not been put to the data owner yet

## Not verified

- The lock and rewrite evidence for the column default is unverified: no
  production-sized copy was available.

## Next action

The next phase is its own change: dual-write and tolerant reads.
