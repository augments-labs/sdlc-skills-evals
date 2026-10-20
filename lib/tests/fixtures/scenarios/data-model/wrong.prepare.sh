# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong model: the lifecycle loses its terminal state, so the
# model no longer says what happens when a promotion's window closes.
sed -i 's#| active | expired | the promotion.s window closes |#| active | withdrawn | the promotion window closes |#' \
  ".sdlc-skills/designs/2026-10-20-discount-engine.md"
sed -i 's#An expired promotion never applies.#A withdrawn promotion never applies.#' \
  ".sdlc-skills/designs/2026-10-20-discount-engine.md"
sed -i 's#A promotion.s window is closed before it is expired.#A promotion window is closed before it is withdrawn.#' \
  ".sdlc-skills/designs/2026-10-20-discount-engine.md"
sed -i '/^| draft | expired | the promotion is withdrawn before it opens |$/d' \
  ".sdlc-skills/designs/2026-10-20-discount-engine.md"
