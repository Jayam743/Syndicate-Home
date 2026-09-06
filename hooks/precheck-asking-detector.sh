#!/usr/bin/env bash
# Precheck-asking-detector — blocks agents that ASK to run precheck/commit
# instead of just RUNNING it.
#
# STOP hook. Reads the CC payload as JSON on STDIN, pulls the last assistant
# text block out of .transcript_path, and matches it against "asking" patterns.
# On a match it emits {"decision":"block","reason":...} and exits 0 (CC block
# contract). Mandatory gates are not optional — execute them, don't ask.
#
# Disable: export PRECHECK_ASKING_HOOK_DISABLED=1
set -uo pipefail

if [[ "${PRECHECK_ASKING_HOOK_DISABLED:-0}" == "1" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || true)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0
fi

LAST_ASSISTANT_TEXT=$(
    tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null |
        jq -rs '
          [.[] | select(.type == "assistant" and (.message.role // "") == "assistant")]
          | last
          | (.message.content // [])
          | map(select(.type == "text") | .text)
          | join(" ")
        ' 2>/dev/null || true
)

if [[ -z "$LAST_ASSISTANT_TEXT" || "$LAST_ASSISTANT_TEXT" == "null" ]]; then
    exit 0
fi

# Patterns that indicate asking permission for something that should just be done.
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
    if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qE "$pattern"; then
        printf '{"decision":"block","reason":"Do not ask permission to run a mandatory gate — ACT. The start of /precheck (or /scp) is unilateral; its checklist is the approval gate. Continue this turn by invoking it now."}'
        exit 0
    fi
done

exit 0
