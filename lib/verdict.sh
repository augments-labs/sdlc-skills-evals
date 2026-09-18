#!/usr/bin/env bash
# Three-valued verdict composition. Sourced, never executed.
#
# verdict_compose <setup> <run> <capture> <checks> <manifest> — each stage is
# pass, fail, or indeterminate. Prints the composed word, exits 0/1/2.
#
# Precedence: any stage indeterminate wins over fail, fail wins over pass.
# An unknown stage word composes indeterminate: the composer cannot prove
# what happened, so it must not print pass or fail.
verdict_compose() {
  [ "$#" -eq 5 ] || { printf 'indeterminate\n'; return 2; }
  local stage
  for stage in "$@"; do
    case "$stage" in pass|fail|indeterminate) ;; *) printf 'indeterminate\n'; return 2;; esac
  done
  for stage in "$@"; do
    [ "$stage" = indeterminate ] && { printf 'indeterminate\n'; return 2; }
  done
  for stage in "$@"; do
    [ "$stage" = fail ] && { printf 'fail\n'; return 1; }
  done
  printf 'pass\n'; return 0
}
