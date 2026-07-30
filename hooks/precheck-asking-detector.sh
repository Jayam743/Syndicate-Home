#!/usr/bin/env bash
# Precheck-asking-detector — blocks agents that ASK to run precheck
# instead of RUNNING it
#
# Detects patterns like:
#   "Shall I run /precheck?"
#   "Would you like me to run precheck?"
#   "Should I execute precheck before committing?"
#
# The correct behavior is: JUST RUN IT. Don't ask.
#
# Install: add to ~/.claude/settings.json under hooks.Stop

set -euo pipefail

OUTPUT="${1:-}"

# Patterns that indicate asking permission for something that should just be done
ASKING_PATTERNS=(
    "[Ss]hall I run.*precheck"
    "[Ww]ould you like me to.*precheck"
    "[Ss]hould I.*precheck"
    "[Cc]an I run.*precheck"
    "[Dd]o you want me to.*precheck"
    "[Ll]et me know if.*precheck"
    "[Ss]hall I run.*scp"
    "[Ww]ould you like me to.*commit"
    "[Ss]hould I commit"
)

for pattern in "${ASKING_PATTERNS[@]}"; do
    if echo "$OUTPUT" | grep -qE "$pattern"; then
        echo "[precheck-detector] BLOCKED: Don't ask — ACT."
        echo "  You asked permission to run a mandatory gate."
        echo "  Correct behavior: just run /precheck (or /scp)."
        echo "  Mandatory actions are not optional — execute them."
        exit 1
    fi
done

exit 0
