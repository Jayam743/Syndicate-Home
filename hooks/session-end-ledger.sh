#!/usr/bin/env bash
# SessionEnd hook — feeds session summary to Ledger's live log
#
# Install: add to ~/.claude/settings.json under "hooks.SessionEnd"
#
# What it does:
# 1. Grabs the session transcript path
# 2. Extracts: what was done (commits, files changed, investigations)
# 3. Appends a one-liner to ~/.syndicate/ledger/current-week.md
#
# This is the bridge between "Ledger knows what you did" and reality.
# Without this hook, Ledger only knows what it can dig up from git logs.

set -euo pipefail

LEDGER_FILE="${HOME}/.syndicate/ledger/current-week.md"
TODAY="$(date +%Y-%m-%d)"

# Ensure ledger file exists
mkdir -p "$(dirname "$LEDGER_FILE")"
if [ ! -f "$LEDGER_FILE" ]; then
    echo "# Week: ${TODAY} →" > "$LEDGER_FILE"
    echo "" >> "$LEDGER_FILE"
fi

# Get the session's working directory and any commits made
SESSION_CWD="${1:-$(pwd)}"
REPO_NAME="$(basename "$SESSION_CWD" 2>/dev/null || echo 'unknown')"

# Check for commits made in this session (last 2 hours)
RECENT_COMMITS=$(git -C "$SESSION_CWD" log --since="2 hours ago" --oneline --author="Jayam\|jpatel\|Jbpatel" 2>/dev/null | head -5)

if [ -n "$RECENT_COMMITS" ]; then
    echo "- [${TODAY}] ${REPO_NAME}: $(echo "$RECENT_COMMITS" | head -1)" >> "$LEDGER_FILE"
fi
