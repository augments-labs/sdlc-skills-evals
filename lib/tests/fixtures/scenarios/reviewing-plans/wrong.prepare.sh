# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong review: it states a version read out of the index
# instead of the version the plan's own content computes to.
sed -i 's|^- Plan version: .*$|- Plan version: plan-v1|' \
  .sdlc-skills/evidence/2026-10-19-tenant-rollout/00-index.review-*-1.md
