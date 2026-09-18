#!/usr/bin/env bash
# Probe scenario for offline runner tests. Sourced by bin/behavior with
# --scenario-dir lib/tests/fake-cli/scenarios, never by a live run.
# Passes iff the runner seeded the fixture (the marker exists).

scenario_opening() { printf 'Probe: confirm the seeded fixture.\n'; }

scenario_setup() { # $1 workdir
  printf 'seeded by the runner\n' > "$1/fixture-marker.txt"
}

scenario_assert() { # $1 workdir
  assert_file "$1/fixture-marker.txt" "runner seeded the fixture"
  assert_result
}
