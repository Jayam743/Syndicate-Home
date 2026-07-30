#!/usr/bin/env bash
# Post-tool test sentinel — creates sentinel file when tests pass
#
# This hook fires AFTER test commands succeed. The sentinel unlocks
# the pre-push-test-gate (Hermes can push once Gauntlet's tests pass).
#
# Install: add to ~/.claude/settings.json under hooks.PostToolUse
# Matcher: "Bash(pytest*|npm test*|go test*|mvn test*|make test*|cargo test*|bun test*)"

set -euo pipefail

SENTINEL="${HOME}/.syndicate/.test-sentinel"
mkdir -p "$(dirname "$SENTINEL")"

# Write sentinel with metadata
cat > "$SENTINEL" << EOF
passed=$(date -Iseconds)
command=${1:-unknown}
cwd=$(pwd)
branch=$(git branch --show-current 2>/dev/null || echo "detached")
EOF

# Silent success — don't clutter agent output
exit 0
