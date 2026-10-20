# shellcheck shell=bash
# shellcheck disable=SC2154
# The review binds the head and base revisions it read, and those revisions
# are the fixture's own commits, so they are computed rather than written.
head="$(git rev-parse pr-42)"
base="$(git rev-parse main)"
dir=".sdlc-skills/evidence/2026-10-20-pr-42"
mkdir -p "$dir"
cat > "$dir/review.md" <<REVIEW
# Review of PR 42: keep the raw token on the session

- PR: local, sdlc-skills-evals, 42, by a contributor
- Reviewed head: $head onto main at $base
- Reviewed by: the maintainer, with independent review (correctness reviewer)
- Recommendation: request changes

## Summary

The change keeps the token the client sent on the session record and compares
it with a plain string equality before the session is returned. The lookup
itself is keyed by the token's digest, so the raw comparison is redundant and
it compares secrets in a way that is not constant-time.

## What was checked

| File or area | What was checked | Result |
| --- | --- | --- |
| src/auth.js | read at the head revision, object reads only | the raw token comparison |

## Findings

### The raw token is kept on the session and compared with string equality

- Blocking: yes
- Where: \`src/auth.js:16\` at the head revision
- What fails: the session record carries the plaintext token, and the equality
  check compares two secrets byte by byte instead of comparing their digests.
- Why: the lookup already resolved the session by the token's SHA-256 digest,
  so the extra comparison adds nothing but the secret on the record.
- Suggested fix: drop the comparison and the stored token, and return the
  session the digest resolved.

## Questions for the author

- Was the raw token needed by anything outside this file? The record does not
  show it.

## Strengths

- The digest lookup is keyed correctly and needs no change.

## Limitations

- The PR's code was not executed; no build, install, or test was run from it.

## Next action

- The author addresses the blocking finding, and the review is redone on the
  new head.
REVIEW
cat > "$dir/ledger.md" <<LEDGER
# Review ledger — PR 42

| Check | State | Bound evidence |
| --- | --- | --- |
| unit suite | not run: PR code not executed | |
| integration suite | not run: PR code not executed | |
| lint | not run: PR code not executed | |

State identity: $head (fetched head revision, recorded by hand).
LEDGER
