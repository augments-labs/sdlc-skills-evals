#!/usr/bin/env bash
# Offline test: verdict_compose precedence. No live run.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../verdict.sh
source "$here/../verdict.sh"

fails=0
check() { # $1 expected-word $2 expected-exit $3... stage words
  local want_word="$1" want_exit="$2"; shift 2
  local got_word got_exit
  got_word="$(verdict_compose "$@")"; got_exit="$?"
  if [ "$got_word" = "$want_word" ] && [ "$got_exit" -eq "$want_exit" ]; then
    printf '  ok    %s -> %s/%s\n' "$*" "$got_word" "$got_exit"
  else
    printf '  FAIL  %s (got %s/%s, want %s/%s)\n' "$*" "$got_word" "$got_exit" "$want_word" "$want_exit"
    fails=1
  fi
}

check pass 0 pass pass pass pass pass
check fail 1 pass fail pass pass pass
check fail 1 fail fail fail fail fail
check indeterminate 2 pass pass pass pass indeterminate
check indeterminate 2 indeterminate fail pass fail pass
check indeterminate 2 fail indeterminate fail fail fail
check indeterminate 2 pass bogus-word pass pass pass

exit "$fails"
