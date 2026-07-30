#!/usr/bin/env bash
# Pipeline state manager — persist/resume pipeline state across sessions
#
# When a session dies mid-pipeline, the state file lets the next session
# know where to pick up.
#
# Usage:
#   ./scripts/pipeline-state.sh start "Scribe → Forge → Athena → Hermes" "fix the thing"
#   ./scripts/pipeline-state.sh advance "Forge"
#   ./scripts/pipeline-state.sh concern "Loki: no index on user_id"
#   ./scripts/pipeline-state.sh complete "MR !147 opened"
#   ./scripts/pipeline-state.sh show
#   ./scripts/pipeline-state.sh clear

set -euo pipefail

STATE_FILE="${HOME}/.syndicate/pipelines/current.json"
mkdir -p "$(dirname "$STATE_FILE")"

ACTION="${1:-show}"
shift || true

case "$ACTION" in
    start)
        PIPELINE="${1:-}"
        TRIGGER="${2:-}"
        cat > "$STATE_FILE" << EOF
{
  "started": "$(date -Iseconds)",
  "trigger": "$TRIGGER",
  "pipeline": "$PIPELINE",
  "current_stage": "$(echo "$PIPELINE" | cut -d'→' -f1 | xargs)",
  "completed_stages": [],
  "concerns": [],
  "status": "active"
}
EOF
        echo "[pipeline] Started: $PIPELINE"
        ;;

    advance)
        STAGE="${1:-}"
        if [ -f "$STATE_FILE" ]; then
            # Simple append — not full JSON manipulation (agents handle that)
            CURRENT=$(grep '"current_stage"' "$STATE_FILE" | sed 's/.*: *"//;s/".*//')
            sed -i "s/\"current_stage\": \".*\"/\"current_stage\": \"$STAGE\"/" "$STATE_FILE"
            # Append completed stage (crude but works for shell)
            sed -i "s/\"completed_stages\": \[/\"completed_stages\": [\"$CURRENT\", /" "$STATE_FILE"
            echo "[pipeline] Advanced: $CURRENT → $STAGE"
        else
            echo "[pipeline] No active pipeline"
            exit 1
        fi
        ;;

    concern)
        CONCERN="${1:-}"
        if [ -f "$STATE_FILE" ]; then
            sed -i "s/\"concerns\": \[/\"concerns\": [\"$CONCERN\", /" "$STATE_FILE"
            echo "[pipeline] Concern logged: $CONCERN"
        fi
        ;;

    complete)
        OUTCOME="${1:-}"
        if [ -f "$STATE_FILE" ]; then
            sed -i "s/\"status\": \"active\"/\"status\": \"complete\"/" "$STATE_FILE"
            # Write evidence packet
            PIPELINE=$(grep '"pipeline"' "$STATE_FILE" | sed 's/.*: *"//;s/".*//')
            TRIGGER=$(grep '"trigger"' "$STATE_FILE" | sed 's/.*: *"//;s/".*//')
            echo "[pipeline] Complete: $OUTCOME"

            # Archive
            ARCHIVE_DIR="${HOME}/.syndicate/pipelines/archive"
            mkdir -p "$ARCHIVE_DIR"
            mv "$STATE_FILE" "${ARCHIVE_DIR}/$(date +%Y%m%d-%H%M%S).json"
        fi
        ;;

    show)
        if [ -f "$STATE_FILE" ]; then
            cat "$STATE_FILE"
        else
            echo "[pipeline] No active pipeline"
        fi
        ;;

    clear)
        rm -f "$STATE_FILE"
        echo "[pipeline] Cleared"
        ;;

    *)
        echo "Usage: pipeline-state.sh {start|advance|concern|complete|show|clear}"
        exit 1
        ;;
esac
