# shellcheck shell=bash
# shellcheck disable=SC2154
# The acceptance layer replaces the project's hollow suite: the old file only
# proved that two modules load, and the floor has to bite on behaviour.
rm -f "test/server.test.js"
