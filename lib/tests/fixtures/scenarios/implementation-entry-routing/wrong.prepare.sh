# shellcheck shell=bash
# shellcheck disable=SC2154
# The minimally wrong run: the agent said what it would do and then edited
# first, so neither skill led the first code edit.
cat > "$STREAM_FILE" <<'INNER'
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"using-sdlc-skills"}},{"type":"tool_use","name":"Edit","input":{"file_path":"src/session.js"}},{"type":"tool_use","name":"Skill","input":{"skill":"test-driven-development"}},{"type":"tool_use","name":"Skill","input":{"skill":"yagni"}}]}}
INNER
