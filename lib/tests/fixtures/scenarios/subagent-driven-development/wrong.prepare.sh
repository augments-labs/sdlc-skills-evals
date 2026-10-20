# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the sixth round ran, so the broken task's artifact
# changed after the breaker had already been spent.
printf 'total: 239\n' > "fixed.txt"
