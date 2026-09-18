# Security Policy

`bin/behavior` and `bin/campaign` launch real agent CLIs in permissive modes,
collect transcripts, read local session logs, and can send run artifacts to a
grader. Treat every run output as sensitive until it is sanitized into a
committed record.

## Reporting a Vulnerability

Do not file public issues or pull requests containing exploitable details,
tokens, session logs with secrets, or private filesystem paths. Report
privately to the maintainer and share only the minimum detail needed to
reproduce the issue.

## Never commit

- `.env` files, API keys, or credential files (`.credentials.json`,
  `auth.json`)
- `results/` run output, except a deliberately recorded campaign
  (`campaign.json`, `runs/*.json`, `chains.json`, `grading/`,
  `benchmark.json`, `feedback.json`, `summary.md`) — never `raw/`, homes,
  transcripts, session logs, or `*.jsonl`
- `workspaces/` iteration scratch, `*.log` files
- local agent config directories (`.claude/`, `.codex/`, `.config/opencode/`
  with credentials)

If a real run prints or captures a secret, rotate the secret before sharing
any artifact derived from that run.

## CI Boundary

Public CI must run only static checks (`shellcheck`, `bin/check`,
`lib/tests/*.sh`). Live `bin/behavior` / `bin/campaign` runs require
credentials and permissive agent CLIs, so they belong in trusted local or
maintainer-controlled environments only. No secret is ever configured on a
CI runner for this repository.
