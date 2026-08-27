#!/usr/bin/env bash
# Godspeed — decaying autonomy mandate system
#
# When the user says "godspeed", a mandate file is created. Agents check it to
# decide whether they can proceed without confirmation. Confidence decays over
# turns; below threshold → checkpoint. "HALT!" revokes immediately.
#
# This is a STOP hook. It reads the CC payload as JSON on STDIN, pulls the last
# assistant message out of .transcript_path (mirrors precheck-asking-detector),
# and scans that text for the ABSOLUTE_GATES / prod keywords. On a gated axis it
# emits {"decision":"block","reason":...} and exits 0 (CC block contract).
#
# The mandate NEVER overrides:
# - prod/production mutations
# - secrets/credentials operations on prod
# - force-push, reset --hard, or other destructive git ops
# - Any action matching the ABSOLUTE_GATES below
set -uo pipefail

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

INPUT=$(cat 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# Pull the last assistant text block out of the transcript (mirror of
# precheck-asking-detector.sh). This is the agent's most recent action/output.
# Also pull the last USER text block: "HALT!" is a USER utterance, not the
# assistant's — the absolute-gate scan runs on the assistant text.
ACTION=""
USER_MSG=""
TRANSCRIPT_OK=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
    TRANSCRIPT_OK=1
    ACTION=$(
        tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null |
            jq -rs '
              [.[] | select(.type == "assistant" and (.message.role // "") == "assistant")]
              | last
              | (.message.content // [])
              | map(select(.type == "text") | .text)
              | join(" ")
            ' 2>/dev/null || true
    )
    USER_MSG=$(
        tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null |
            jq -rs '
              [.[] | select(.type == "user" and (.message.role // "") == "user")]
              | last
              | (.message.content // [])
              | if type == "array" then
                  map(select(.type == "text") | .text) | join(" ")
                else . end
            ' 2>/dev/null || true
    )
fi

if [[ "$ACTION" == "null" ]]; then
    ACTION=""
fi
if [[ "$USER_MSG" == "null" ]]; then
    USER_MSG=""
fi

# --- Check for HALT command (a USER utterance) ---
# Scan the last user message for HALT and revoke the mandate immediately.
if printf '%s' "$USER_MSG" | grep -qiF -- "HALT"; then
    if [[ -f "$MANDATE_FILE" ]]; then
        rm -f "$MANDATE_FILE"
        rm -f "$STATE_FILE"
    fi
    exit 0
fi

# --- Check absolute gates (these ALWAYS block, godspeed or not) ---
# Extended-regex match (-E) with end-of-options (--): the -- lets gate values
# that start with a dash (e.g. "--force") be treated as patterns not grep flags,
# while -E keeps the .*-style gates (e.g. "terraform apply.*prod") matching as regex.
for gate in "${ABSOLUTE_GATES[@]}"; do
    if printf '%s' "$ACTION" | grep -qiE -- "$gate"; then
        jq -nc --arg g "$gate" '{decision:"block",reason:("Gated axis detected (prod/deploy/irreversible keyword: " + $g + "). This action requires explicit user approval — the Godspeed mandate does not override the ABSOLUTE rule.")}'
        exit 0
    fi
done

# --- Transcript unavailable while a mandate is active: fail closed ---
# If we could not read the transcript, the absolute-gate scan above saw nothing.
# Rather than silently allow an active mandate to proceed, checkpoint.
if [[ "$TRANSCRIPT_OK" -eq 0 && -f "$MANDATE_FILE" ]]; then
    jq -nc '{decision:"block",reason:"Godspeed mandate is active but the transcript is unavailable — cannot verify against the ABSOLUTE gates. Checkpointing — confirm to continue, or say HALT! to revoke the mandate."}'
    exit 0
fi

# --- If no mandate, standard behavior (don't block) ---
if [[ ! -f "$MANDATE_FILE" ]]; then
    exit 0
fi

# --- Mandate is active: check decay ---
TURNS_SINCE=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
TURNS_SINCE=$((TURNS_SINCE + 1))
echo "$TURNS_SINCE" > "$STATE_FILE"

# Decay formula: bar = turns / expected_total (default 20 turns per pipeline).
# Pure integer arithmetic (no bc dependency): work in percent (x100).
EXPECTED_TOTAL=20
BAR_PCT=$(( TURNS_SINCE * 100 / EXPECTED_TOTAL ))

# Confidence: 80% if tests ran recently, 40% otherwise.
if [[ -f "${HOME}/.syndicate/.test-sentinel" ]]; then
    CONFIDENCE_PCT=80
else
    CONFIDENCE_PCT=40
fi

# Compare: if bar > confidence, checkpoint (don't revoke, just this turn).
if (( BAR_PCT > CONFIDENCE_PCT )); then
    jq -nc --arg t "$TURNS_SINCE" --arg e "$EXPECTED_TOTAL" '{decision:"block",reason:("Godspeed confidence decayed (turn " + $t + "/" + $e + "). Checkpointing — confirm to continue, or say HALT! to revoke the mandate.")}'
    exit 0
fi

# Mandate active, confidence sufficient — allow.
exit 0
