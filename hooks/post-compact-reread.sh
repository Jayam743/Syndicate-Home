#!/usr/bin/env bash
# Post-compact re-read — after context compaction, re-read critical state
#
# When the context window gets compacted, agents lose awareness of:
# - Current pipeline state
# - Active godspeed mandate
# - Evidence packet in progress
# - Toolkit reference
#
# This hook outputs reminders so the next turn starts with context.
#
# Install: add to ~/.claude/settings.json under hooks.PostCompact
# (or SessionStart for post-/clear revival)

set -euo pipefail

SYNDICATE_DIR="${HOME}/.syndicate"
PIPELINE_STATE="${SYNDICATE_DIR}/pipelines/current.json"
MANDATE_FILE="${SYNDICATE_DIR}/.godspeed"

echo "[syndicate-reread] Context was compacted. Re-establishing state:"

# 1. Check active pipeline
if [ -f "$PIPELINE_STATE" ]; then
    echo "  ⚡ Active pipeline detected:"
    cat "$PIPELINE_STATE" 2>/dev/null | head -20
    echo ""
fi

# 2. Check godspeed mandate
if [ -f "$MANDATE_FILE" ]; then
    echo "  🚀 Godspeed mandate is ACTIVE"
    cat "$MANDATE_FILE" 2>/dev/null
    echo ""
fi

# 3. Remind about toolkit
echo "  📋 Toolkit reference: config/toolkit.md"
echo "  📋 Agent definitions: agents/*.md"
echo ""
echo "  Re-read CLAUDE.md and config/toolkit.md to restore full context."
