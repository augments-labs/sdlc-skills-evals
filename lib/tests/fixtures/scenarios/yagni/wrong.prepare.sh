# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong change: the tiers work, but nothing in the new code
# explains why the rule is what it is.
sed -i '/^[[:space:]]*\/\//d' "src/pricing.js"
