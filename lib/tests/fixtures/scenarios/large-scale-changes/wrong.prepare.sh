# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong manifest: one shard per package. The ownership file
# gives two owners, so @team-platform is handed two review requests where one
# would do.
sed -i 's#| platform-packages | @team-platform | `packages/core/src/\*\*`, `packages/api/src/\*\*` | 6 | yes — the suite passes on this shard alone against the base | pending | none |#| core-package | @team-platform | `packages/core/src/**` | 3 | yes | pending | none |#' \
  ".sdlc-skills/designs/2026-10-20-rename-legacy-call-shards.md"
sed -i 's#| web-package | @team-web | `packages/web/src/\*\*` | 3 | yes — the suite passes on this shard alone against the base | pending | none |#| api-package | @team-platform | `packages/api/src/**` | 3 | yes | pending | none |\n| web-package | @team-web | `packages/web/src/**` | 3 | yes | pending | none |#' \
  ".sdlc-skills/designs/2026-10-20-rename-legacy-call-shards.md"
