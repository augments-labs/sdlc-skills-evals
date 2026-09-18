#!/usr/bin/env bash
# Probe scenario whose assertions never execute: the runner must refuse
# green (indeterminate, stage=checks), never pass it.

scenario_opening() { printf 'Probe: a scenario that checks nothing.\n'; }

scenario_setup() { # $1 workdir
  printf 'seeded by the runner\n' > "$1/fixture-marker.txt"
}

scenario_assert() { # $1 workdir
  : # deliberately no check ran
}
