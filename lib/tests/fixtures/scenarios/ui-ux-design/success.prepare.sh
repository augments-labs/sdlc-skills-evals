# shellcheck shell=bash
# shellcheck disable=SC2154
# The governed preview leaves a startup record; the scenario reads that record
# and never a live probe. The record's root binds it to THIS workdir.
cat > "/tmp/serve-preview.scenario-contracts-$$.log" <<INNER
{"event":"server-started","root":"$d/site","url":"http://127.0.0.1:8731/?key=fixture-session-key","pid":999999}
INNER
