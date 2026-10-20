# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the plan was executed without the yagni pair
# leading the first code edit.
cat > "$STREAM_FILE" <<'INNER'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"ui-ux-design"}},{"type":"tool_use","name":"Skill","input":{"skill":"writing-plans"}},{"type":"tool_use","name":"Skill","input":{"skill":"executing-plans"}},{"type":"tool_use","name":"Skill","input":{"skill":"test-driven-development"}},{"type":"tool_use","name":"Edit","input":{"file_path":"src/page.js"}}]}}
INNER
