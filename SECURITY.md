# Security Policy

`bin/evaluate`, `bin/triggering`, `bin/optimize-description`, and
`bin/grade --harness` launch real agent CLIs in permissive modes, collect raw
streams, and send produced files and transcript text to a grader session.
Only the user starts one, from their own terminal, after its `--dry-run`
(`README.md` `## Running it yourself`); no agent working on this repository
ever does (`CLAUDE.md`). Treat every run output as sensitive until it is sanitized into a
committed record.

## Reporting a Vulnerability

Do not file public issues or pull requests containing exploitable details,
tokens, session logs with secrets, or private filesystem paths. Report
privately to the maintainer and share only the minimum detail needed to
reproduce the issue.

## Never commit

- `.env` files, API keys, or credential files (`.credentials.json`,
  `auth.json`)
- `results/` run output, except a deliberately recorded one (what
  `bin/report` copies: `benchmark.json`, `benchmark.md`, `feedback.json`) —
  never `raw/`, homes, transcripts, session logs, or `*.jsonl`
- `workspaces/` iterations (produced `outputs/`, raw streams, grader
  transcripts), `*.log` files
- local agent config directories (`.claude/`, `.codex/`, `.config/opencode/`
  with credentials)

If a real run prints or captures a secret, rotate the secret before sharing
any artifact derived from that run.

## CI Boundary

Public CI must run only static checks (`shellcheck`, `bin/check`,
`lib/tests/*.sh`), the suites under `lib/tests/ci-static.sh`'s tripwire,
which fails the job if any of them reaches a real agent CLI. Live runs
require the user's own logged-in CLI and permissive modes, so they belong in
the user's own terminal only. No secret is ever configured on a
CI runner for this repository.
