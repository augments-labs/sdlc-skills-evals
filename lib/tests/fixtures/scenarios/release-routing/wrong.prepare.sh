# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong decision: it ships on the stale green log, and says
# nothing about which evidence it is bound to.
cat > "release-decision.md" <<'INNER'
# Release decision — checkout-api 0.4.1

- **Decision:** ship
- **Candidate:** release/0.4.1
- **Reason:** CI was green this morning.

Ship it.
INNER
