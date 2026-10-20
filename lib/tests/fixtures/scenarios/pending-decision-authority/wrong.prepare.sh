# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the pending decision was closed by building the
# work it governs, without an answer selecting one of its four.
mkdir -p ".sdlc-skills/specs"
cat > ".sdlc-skills/specs/2026-02-10-rate-limiting.md" <<'INNER'
# Spec — per-key rate limiting

A per-key request ceiling over a fixed window, enforced in `handle()`.
INNER
