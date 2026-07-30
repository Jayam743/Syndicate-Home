#!/usr/bin/env bash
# Arm the Godspeed mandate
#
# Called when user says "godspeed" — creates the mandate file
# that tells the stop hook to allow autonomous operation.
#
# Usage: source this from a skill or call directly
#   ./hooks/godspeed-arm.sh [expected_turns]

set -euo pipefail

MANDATE_FILE="${HOME}/.syndicate/.godspeed"
STATE_FILE="${HOME}/.syndicate/.godspeed-state"

mkdir -p "${HOME}/.syndicate"

# Write mandate
cat > "$MANDATE_FILE" << EOF
armed=$(date -Iseconds)
expected_turns=${1:-20}
armed_by=user
EOF

# Reset turn counter
echo "0" > "$STATE_FILE"

echo "[godspeed] Mandate armed. Agents will operate autonomously."
echo "  Decay: checkpoints after ~$(( ${1:-20} * 80 / 100 )) turns (80% confidence)"
echo "  Say HALT! to revoke at any time."
echo "  ABSOLUTE gates (prod, destroy, force) still require approval."
