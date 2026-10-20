# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong page: the `[x] done with concerns` task was counted as
# done, so the rollup claims six of nine.
sed -i 's|billing-retry: 5/9 tasks done|billing-retry: 6/9 tasks done|' \
  ".sdlc-skills/views/index.html"
