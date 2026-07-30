#!/usr/bin/env bash
# Pre-push test gate — blocks git push unless tests have been run
#
# How it works:
# - Gauntlet (or any test runner) creates a sentinel file when tests pass
# - This hook checks for that sentinel before allowing push
# - Sentinel expires after 30 minutes (tests must be recent)
#
# Install: add to ~/.claude/settings.json under hooks.PreToolUse
# Matcher: "Bash(git push*)"
#
# Skip for integration branches (kahuna/*, release/*) where CI handles it.

set -euo pipefail

SENTINEL="${HOME}/.syndicate/.test-sentinel"
MAX_AGE_SECONDS=1800  # 30 minutes

# Allow integration branches through (CI gates them instead)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ "$CURRENT_BRANCH" == kahuna/* ]] || [[ "$CURRENT_BRANCH" == release/* ]]; then
    exit 0
fi

# Check sentinel exists
if [ ! -f "$SENTINEL" ]; then
    echo "[test-gate] BLOCKED: No test sentinel found."
    echo "  Run your tests first (Gauntlet creates the sentinel on pass)."
    echo "  Sentinel location: ${SENTINEL}"
    exit 1
fi

# Check sentinel freshness
SENTINEL_AGE=$(( $(date +%s) - $(stat -c %Y "$SENTINEL" 2>/dev/null || stat -f %m "$SENTINEL" 2>/dev/null || echo 0) ))
if [ "$SENTINEL_AGE" -gt "$MAX_AGE_SECONDS" ]; then
    echo "[test-gate] BLOCKED: Test sentinel is stale (${SENTINEL_AGE}s old, max ${MAX_AGE_SECONDS}s)."
    echo "  Re-run tests to create a fresh sentinel."
    rm -f "$SENTINEL"
    exit 1
fi

# Sentinel is fresh — allow push
exit 0
