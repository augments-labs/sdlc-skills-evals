# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong record: the contract phase names an application
# rollback. The contract is the point of no return, and an application
# rollback cannot undo it.
sed -i 's|restore from the retained backup, with its recovery time; an application rollback to 1.4.0 ends here|the previous release, 1.4.0|' \
  ".sdlc-skills/designs/2026-10-20-tenant-ref-schema-change-expand.md"
