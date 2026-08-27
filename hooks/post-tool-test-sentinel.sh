#!/usr/bin/env bash
# Post-tool test sentinel — writes the sentinel file when tests pass.
#
# PostToolUse hook. Wired under a bare "Bash" matcher, so this script filters
# internally for test/lint/validate commands and no-ops on everything else.
# The sentinel unlocks pre-push-test-gate.sh (Hermes can push once tests pass).
#
# PostToolUse hooks cannot block — this one only writes the sentinel, so it
# emits no decision JSON. Reads the CC payload as JSON on STDIN
# (.tool_input.command + the tool exit info); writes only on success.
#
# Recognized: pytest, python -m pytest, npm test, npx vitest, make test/lint,
# ./scripts/ci/{validate,test}.sh, ruff check, cargo test, go test, bun test,
# mvn test.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // .tool_result.exit_code // 1' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only fire for test/lint/validate commands.
TEST_PATTERN='(pytest|python[0-9.]* -m pytest|npm test|npx vitest|make (test|lint|check)|\./scripts/ci/(validate|test)\.sh|ruff check|cargo test|go test|mvn test|bun test)'
if ! printf '%s' "$COMMAND" | grep -qE "$TEST_PATTERN"; then
    exit 0
fi

# Only mark the sentinel on explicit success. A missing/unparseable exit code
# resolves to 1 above (fail-closed): the sentinel is written ONLY when the
# resolved exit code is exactly 0.
if [[ "$EXIT_CODE" != "0" ]]; then
    exit 0
fi

SENTINEL="${HOME}/.syndicate/.test-sentinel"
mkdir -p "$(dirname "$SENTINEL")"

cat > "$SENTINEL" <<EOF
passed=$(date -Iseconds)
command=$(printf '%s' "$COMMAND" | head -c 120)
cwd=$(pwd)
branch=$(git branch --show-current 2>/dev/null || echo "detached")
EOF

exit 0
