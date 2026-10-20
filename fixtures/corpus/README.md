# fixtures/corpus/

The tracked material the seeded trees are built from.

`project/` is the project the descriptions runner seeds each query with: the
source files, the ticket, the session record. `plans/` is the plan material,
staged under `.sdlc-skills/plans/` in the workdir. `evidence/` is a delegated
plan's run ledger, staged under `.sdlc-skills/evidence/`.

It is a root of its own, and not the project's own `.sdlc-skills/` directory.
The repository ignores that one — the lab's own plans, ledgers and run state
are meant to stay local — so a fixture placed there would be present in the
working tree and absent from the commit: present when a corpus is written,
gone when the commit is extracted. A plan fixture is a REPRESENTATION of a
plan, staged where a plan lives; it is not the lab's own plan, and it is
committed here so that what a corpus names is what the repository holds.

The same material appears in two shapes, because the two corpora run against
two different workdirs:

- the **description-query** tree is a throwaway workdir the runner builds, so
  a plan lands at `.sdlc-skills/plans/{{YYYY-MM-DD}}-{{topic}}/`, where a
  project keeps one;
- the **output-eval** tree is a skill's own `files/` directory, copied into
  the run workdir, so a plan lands at `plans/{{YYYY-MM-DD}}-{{topic}}/`: a
  path the repository tracks.

A plan's identity covers its index and its task files, not its ledger, so the
two copies keep the same version while naming their own locations.

The session record is `.ndjson` — newline-delimited JSON, the format the
upstream session-store reference describes — because the repository ignores
`*.jsonl`, and a fixture under an ignored name would be present in the
working tree and absent from the commit.
