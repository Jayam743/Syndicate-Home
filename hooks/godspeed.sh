#!/usr/bin/env bash
# Godspeed — decaying autonomy mandate system
#
# When the user says "godspeed", a mandate file is created. Agents check it to
# decide whether they can proceed without confirmation. Confidence decays over
# turns; below threshold → checkpoint. "HALT!" revokes immediately.
#
# This is a STOP hook. It reads the CC payload as JSON on STDIN, pulls the last
# assistant message out of .transcript_path (mirrors precheck-asking-detector),
# and scans the tool_use COMMANDS (not prose) of that message for the
# ABSOLUTE_GATES / prod keywords. On a gated axis it emits
# {"decision":"block","reason":...} and exits 0 (CC block contract).
#
# The mandate NEVER overrides:
# - prod/production mutations
# - secrets/credentials operations on prod
# - force-push, reset --hard, or other destructive git ops
# - Any action matching the ABSOLUTE_GATES below
set -uo pipefail

MANDATE_FILE="${HOME}/.syndicate/.godspeed"
STATE_FILE="${HOME}/.syndicate/.godspeed-state"

# --- Worktree-keyed sentinel: shared key derivation (B′, issue #30) ---
# Resolve a stable per-worktree key from a command's cwd. The key is the sha1
# of the repo TOPLEVEL (`git -C <cwd> rev-parse --show-toplevel`). Honors an
# explicit `git -C <path>` inside the acted-on command. Prints the key on
# success; prints nothing and returns 1 on failure.
# FAIL CLOSED: callers MUST treat a non-zero return as "no key" and NEVER fall
# back to a shared global sentinel. This function is duplicated verbatim in
# post-tool-test-sentinel.sh and pre-push-test-gate.sh — keep the copies in sync.
syndicate_sentinel_key() {
    local cwd="$1" cmd="${2:-}" base gitc toplevel key
    # Honor an explicit `git -C <path>` in the command (takes precedence over cwd).
    gitc=$(printf '%s\n' "$cmd" \
        | grep -oE '(^|[[:space:]])git[[:space:]]+-C[[:space:]]+[^[:space:]]+' \
        | head -n1 | grep -oE '[^[:space:]]+$' || true)
    gitc=${gitc%\"}
    gitc=${gitc#\"}
    if [[ -n "$gitc" ]]; then
        base="$gitc"
    else
        base="$cwd"
    fi
    [[ -n "$base" ]] || return 1
    toplevel=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -n "$toplevel" ]] || return 1
    if command -v sha1sum >/dev/null 2>&1; then
        key=$(printf '%s' "$toplevel" | sha1sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        key=$(printf '%s' "$toplevel" | shasum | awk '{print $1}')
    else
        return 1
    fi
    [[ -n "$key" ]] || return 1
    printf '%s' "$key"
}

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
    "deploy.*prod"
)

INPUT=$(cat 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

# Pull the last assistant message's tool_use commands out of the transcript.
# This is the agent's most recent real action(s) — not its prose. Also pull the
# last USER text block: "HALT!" is a USER utterance, not the assistant's — the
# absolute-gate scan runs on the assistant's tool_use commands.
ACTION=""
USER_MSG=""
TRANSCRIPT_OK=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" && -r "$TRANSCRIPT_PATH" ]]; then
    TRANSCRIPT_OK=1
    # Extract the tool_use COMMANDS from the LAST assistant message (not prose).
    # Dispatch/planning/informational tools are blacklisted so their inputs (which
    # can quote prod keywords in prose, e.g. an Agent prompt) never trip the gates.
    # In-scope by default: Bash/Edit/Write/MultiEdit/NotebookEdit/mcp__* (blacklist).
    # FAIL-CLOSED: if jq errors, TRANSCRIPT_OK=0 so the checkpoint branch fires.
    ACTION=$(
        tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null |
            jq -rs '
              [.[] | select(.type == "assistant" and (.message.role // "") == "assistant")]
              | last
              | (.message.content // [])
              | [ .[]
                  | select(.type == "tool_use")
                  | select((.name // "") as $n | ["Agent","TodoWrite","Read","Grep","Glob","AskUserQuestion","ToolSearch","WebFetch","NotebookRead","Skill"] | index($n) | not)
                  | ((.input // {}) | tojson) ]
              | join("\n---\n")
            ' 2>/dev/null
    ) || TRANSCRIPT_OK=0
    USER_MSG=$(
        tail -n 500 "$TRANSCRIPT_PATH" 2>/dev/null |
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
# while -E keeps the .*-style gates (e.g. "deploy.*prod") matching as regex.
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

# Confidence: 80% if tests ran recently for THIS worktree, 40% otherwise.
# Repointed to the per-worktree sentinel (B′, issue #30): the STOP payload
# carries .cwd, so we resolve the same key the gate/writer use. FAIL CLOSED to
# the 40% floor if the worktree can't be resolved (never assume tests ran).
SENTINEL_KEY=$(syndicate_sentinel_key "$CWD" "") || SENTINEL_KEY=""
if [[ -n "$SENTINEL_KEY" && -f "${HOME}/.syndicate/sentinels/${SENTINEL_KEY}" ]]; then
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
