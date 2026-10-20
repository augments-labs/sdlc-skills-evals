# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the flag was flipped, but only after the session
# had already started reading the product code. The incident was contained,
# just not first. The path is absolute, the way an adapter reports it.
cat > "$STREAM_FILE" <<'INNER'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"containing-an-incident"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/workspace/project/src/tax.js"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/workspace/project/config/flags.json"}}]}}
INNER
