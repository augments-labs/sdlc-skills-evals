# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the cycle ended at green, and the skill that owns
# the DONE boundary never fired.
cat > "$STREAM_FILE" <<'INNER'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"using-sdlc-skills"}},{"type":"tool_use","name":"Skill","input":{"skill":"test-driven-development"}},{"type":"tool_use","name":"Skill","input":{"skill":"yagni"}},{"type":"tool_use","name":"Write","input":{"file_path":"src/allowance.js"}}]}}
INNER
