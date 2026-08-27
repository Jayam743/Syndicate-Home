#!/usr/bin/env bash
# Pre-push test gate — blocks git push unless tests have been run
#
# PreToolUse hook. Wired under a bare "Bash" matcher; this script MUST filter
# internally for `git push` and no-op on every other Bash command — otherwise
# it gates every single Bash call (catastrophic UX).
#
# How it works:
# - A companion PostToolUse hook (post-tool-test-sentinel.sh) writes a sentinel
#   file when tests pass.
# - This hook checks for that sentinel before allowing push.
# - Sentinel expires after 30 minutes (tests must be recent).
#
# Integration branches (kahuna/*, release/*) skip the gate — CI handles them.
#
# On block it emits {"decision":"block","reason":...} and exits 0 (CC block
# contract). Override with PUSH_GATE_DISABLED=1.
set -uo pipefail

if [[ "${PUSH_GATE_DISABLED:-0}" == "1" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only gate actual push commands. Without this the "Bash" matcher would gate
# every Bash call in the session.
if ! printf '%s' "$COMMAND" | grep -qE '^\s*git\s+push'; then
    exit 0
fi

SENTINEL="${HOME}/.syndicate/.test-sentinel"
MAX_AGE_SECONDS=1800  # 30 minutes

# Allow integration branches through (CI gates them instead).
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$CURRENT_BRANCH" == kahuna/* ]] || [[ "$CURRENT_BRANCH" == release/* ]]; then
    exit 0
fi

# Check sentinel exists.
if [[ ! -f "$SENTINEL" ]]; then
    printf '{"decision":"block","reason":"Cannot push untested code — no test sentinel found. Run the project test/lint/validate tooling first (Gauntlet writes the sentinel on pass). The push will be allowed once tests pass. Set PUSH_GATE_DISABLED=1 to override."}'
    exit 0
fi

# Check sentinel freshness.
SENTINEL_AGE=$(( $(date +%s) - $(stat -c %Y "$SENTINEL" 2>/dev/null || stat -f %m "$SENTINEL" 2>/dev/null || echo 0) ))
if [[ "$SENTINEL_AGE" -gt "$MAX_AGE_SECONDS" ]]; then
    rm -f "$SENTINEL"
    printf '{"decision":"block","reason":"Test sentinel is stale (%ss old, max %ss). Re-run tests to create a fresh sentinel before pushing. Set PUSH_GATE_DISABLED=1 to override."}' "$SENTINEL_AGE" "$MAX_AGE_SECONDS"
    exit 0
fi

# Sentinel is fresh — allow push.
exit 0
