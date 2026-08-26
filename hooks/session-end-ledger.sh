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
#
# Dedup: SHA-keyed idempotency — never appends a commit line if the SHA
# is already present in the ledger file (fixes 13x duplicate observation).

set -euo pipefail

LEDGER_FILE="${HOME}/.syndicate/ledger/current-week.md"
TODAY="$(date +%Y-%m-%d)"

# Ensure ledger file exists
mkdir -p "$(dirname "$LEDGER_FILE")"
if [ ! -f "$LEDGER_FILE" ]; then
    echo "# Week: ${TODAY} ->" > "$LEDGER_FILE"
    echo "" >> "$LEDGER_FILE"
fi

# Get the session's working directory and any commits made
SESSION_CWD="${1:-$(pwd)}"
REPO_NAME="$(basename "$SESSION_CWD" 2>/dev/null || echo 'unknown')"

# Log ALL new commits from the last 2 hours, each dedup-guarded by SHA
RECENT_COMMITS="$(git -C "$SESSION_CWD" log --since="2 hours ago" --oneline --author="Jayam\|jpatel\|Jbpatel" 2>/dev/null || true)"

if [ -n "$RECENT_COMMITS" ]; then
    while IFS= read -r commit_line; do
        [ -z "$commit_line" ] && continue
        # Extract the short SHA (first field)
        sha="${commit_line%% *}"
        # Skip if this SHA is already in the ledger
        if grep -q "$sha" "$LEDGER_FILE" 2>/dev/null; then
            continue
        fi
        echo "- [${TODAY}] ${REPO_NAME}: ${commit_line}" >> "$LEDGER_FILE"
    done <<< "$RECENT_COMMITS"
fi
