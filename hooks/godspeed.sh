#!/usr/bin/env bash
# Godspeed — decaying autonomy mandate system
#
# When the user says "godspeed", a mandate file is created.
# Agents check this file to determine if they can proceed without confirmation.
# Confidence decays over turns. Below threshold → checkpoint.
# "HALT!" revokes immediately.
#
# This is a STOP hook — it fires after agent output and can block.
#
# Install: add to ~/.claude/settings.json under hooks.Stop
#
# The mandate NEVER overrides:
# - prod/production mutations
# - secrets/credentials operations on prod
# - force-push, reset --hard, or other destructive git ops
# - Any action matching the ABSOLUTE_GATES below

set -euo pipefail

MANDATE_FILE="${HOME}/.syndicate/.godspeed"
STATE_FILE="${HOME}/.syndicate/.godspeed-state"

# --- ABSOLUTE GATES (never overridden by godspeed) ---
ABSOLUTE_GATES=(
    "production"
    "prod-deploy"
    "--force"
    "reset --hard"
    "drop table"
    "drop database"
    "rm -rf /"
    "destroy"
    "terraform destroy"
    "terraform apply.*prod"
    "aws.*prod.*delete"
    "aws.*prod.*terminate"
    "vault.*prod"
)

# Get the agent's last output/action (passed via stdin or $1)
ACTION="${1:-}"

# --- Check for HALT command ---
if echo "$ACTION" | grep -qi "HALT\|halt!"; then
    if [ -f "$MANDATE_FILE" ]; then
        rm -f "$MANDATE_FILE"
        rm -f "$STATE_FILE"
        echo "[godspeed] MANDATE REVOKED. All operations now require confirmation."
    fi
    exit 0
fi

# --- Check absolute gates (these ALWAYS block, godspeed or not) ---
for gate in "${ABSOLUTE_GATES[@]}"; do
    if echo "$ACTION" | grep -qi "$gate"; then
        echo "[godspeed-STOP] Gated axis detected (prod/deploy/irreversible keyword)."
        echo "  This action requires explicit user approval."
        echo "  The Godspeed mandate does not override the ABSOLUTE rule."
        exit 1
    fi
done

# --- If no mandate, standard behavior (don't block) ---
if [ ! -f "$MANDATE_FILE" ]; then
    exit 0
fi

# --- Mandate is active: check decay ---
TURNS_SINCE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
TURNS_SINCE=$((TURNS_SINCE + 1))
echo "$TURNS_SINCE" > "$STATE_FILE"

# Decay formula: bar = turns / expected_total
# Expected total defaults to 20 turns for a typical pipeline
EXPECTED_TOTAL=20
BAR=$(echo "scale=2; $TURNS_SINCE / $EXPECTED_TOTAL" | bc 2>/dev/null || echo "0.5")

# Confidence: 80% if tests ran recently, 40% otherwise
if [ -f "${HOME}/.syndicate/.test-sentinel" ]; then
    CONFIDENCE="0.80"
else
    CONFIDENCE="0.40"
fi

# Compare: if bar > confidence, checkpoint
SHOULD_CHECKPOINT=$(echo "$BAR > $CONFIDENCE" | bc 2>/dev/null || echo "0")
if [ "$SHOULD_CHECKPOINT" = "1" ]; then
    echo "[godspeed] Confidence decayed (turn ${TURNS_SINCE}/${EXPECTED_TOTAL})."
    echo "  Checkpointing — confirm to continue, or say HALT! to stop."
    # Don't revoke mandate, just checkpoint this turn
    exit 1
fi

# Mandate active, confidence sufficient — allow
exit 0
