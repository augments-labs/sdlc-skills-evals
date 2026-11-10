<!--
BEFORE SUBMITTING: this repo is the eval lab for sdlc-skills.
It runs agent CLIs in permissive modes and can handle sensitive transcripts.
Low-evidence, speculative, or bundled PRs will be closed.
-->

## What problem are you trying to solve?
<!-- Describe the specific failure, security gap, eval gap, or user-observed behavior.
     "Hardening" or "improving" is not enough on its own. What broke, leaked,
     became unsafe, or produced an unreliable eval signal? -->

## What does this PR change?
<!-- 1-3 sentences. Keep this to the actual files/behavior changed. -->

## Relationship to sdlc-skills
<!-- Plugin pin under test (the inventory pins commit
     40f8ff4c532da29b286b4d06ecf4516a4a093a7d, 11.2.0, in config/upstream-inventory.json).
     If this changes skill behavior, harness loading, or eval methodology,
     describe the expected before/after signal and why it belongs here. -->

## Security and eval-lab checklist
- [ ] This PR does not commit API keys, `.env` files, session logs, `results/`, or other run artifacts
- [ ] This PR does not cause CI to run live agent evals or call model APIs, and needs no credentials or secrets in CI (this lab uses none — harnesses authenticate through the operator's own CLI setup, never through keys in the repo)
- [ ] If this touches dangerous-mode backend flags, shell execution, environment inheritance, or log collection, the risk is explained below
- [ ] If this adds or changes an eval set, a `[check:` assertion, a harness adapter, or a grader prompt, I considered how untrusted input could affect shell execution

Risk notes:
<!-- Required for changes touching backends, setup helpers, assertions, session launch, logs, or verifier input. Otherwise write "N/A". -->

## Existing work
- [ ] I searched for related open and closed PRs/issues/tickets
- Related work: <!-- links or "none found" -->

## Tests
<!-- Paste exact commands and outcomes. At minimum, explain whether these ran:
     shellcheck -S warning <the file globs in .github/workflows/static.yml>
     bash bin/check
     per-file: bash lib/tests/<name>.sh

     A live run (bin/evaluate, bin/triggering, bin/optimize-description without
     --dry-run, or bin/grade --harness) is started by the user only, never by an
     agent, and never in public CI. If one backs this PR, name its record path
     and the --dry-run that priced it. -->

## Human review
- [ ] A maintainer has reviewed the complete proposed diff before merge
