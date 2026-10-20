# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong surface: one direction was described and the other
# never rendered, so there is nothing to compare.
sed -i 's|<section class="variant variant-2">|<section class="variant variant-1">|' \
  ".sdlc-skills/designs/2026-10-20-nordwind/visuals/hero.html"
