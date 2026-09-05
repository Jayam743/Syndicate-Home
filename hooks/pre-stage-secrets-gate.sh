#!/usr/bin/env bash
# Pre-stage secrets gate — blocks git add of files matching secret patterns
#
# PreToolUse hook. Wired under a bare "Bash" matcher; this script filters
# internally for `git add` / `git stage` and no-ops on everything else.
#
# Reads the CC hook payload as JSON on STDIN (.tool_input.command).
# On a match it emits {"decision":"block","reason":...} and exits 0 —
# the CC harness's block contract (never a bare exit 1).
#
# Fails CLOSED: any internal error blocks. Override with SECRETS_GATE_DISABLED=1.
set -uo pipefail

trap 'printf "{\"decision\":\"block\",\"reason\":\"secrets-gate internal error — failing closed. Set SECRETS_GATE_DISABLED=1 to override.\"}"; exit 0' ERR

if [[ "${SECRETS_GATE_DISABLED:-0}" == "1" ]]; then
    # Explicit operator override — stand down.
    exit 0
fi

INPUT=$(cat 2>/dev/null || true)

# Fail CLOSED on malformed input: if stdin is non-empty but not valid JSON, the
# jq extraction below would silently yield an empty COMMAND and allow. Block.
if [[ -n "$INPUT" ]] && ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
    jq -nc --arg r "secrets-gate received malformed hook input (invalid JSON) — failing closed. Set SECRETS_GATE_DISABLED=1 to override." '{decision:"block",reason:$r}'
    exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only gate git add / git stage commands.
if ! printf '%s' "$COMMAND" | grep -qE '^\s*git\s+(add|stage)'; then
    exit 0
fi

# Blocked file patterns (by name)
BLOCKED_PATTERNS=(
    '\.env$'
    '\.env\.'
    '\.key$'
    '\.pem$'
    '\.p12$'
    '\.pfx$'
    '\.jks$'
    'credentials\.json'
    'service[-_]account.*\.json'
    '\.tfvars$'
    'secrets\.ya?ml$'
    '\.secrets$'
    'id_rsa'
    'id_ed25519'
)

# Check each token in the command against the blocked patterns.
BLOCKED_FILES=""
for pattern in "${BLOCKED_PATTERNS[@]}"; do
    matches=$(printf '%s' "$COMMAND" | grep -oE "[^ ]+" | grep -E "$pattern" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        BLOCKED_FILES="${BLOCKED_FILES}${matches} "
    fi
done

if [[ -n "$BLOCKED_FILES" ]]; then
    BLOCKED_FILES=$(printf '%s' "$BLOCKED_FILES" | tr '\n' ' ' | tr -s ' ')
    jq -nc --arg r "Potential secrets detected in staged files: $BLOCKED_FILES. Add them to .gitignore and store secrets in an env var or secret manager. If intentional, stage with git add --force (not recommended) or set SECRETS_GATE_DISABLED=1." '{decision:"block",reason:$r}'
    exit 0
fi

# Also gate broad adds that might sweep in untracked secret-pattern files.
if printf '%s' "$COMMAND" | grep -qE '(git add \.|git add -A|git add --all)'; then
    DANGEROUS=$(git ls-files --others --exclude-standard 2>/dev/null | grep -E '(\.env|\.key|\.pem|credentials|\.tfvars|secrets\.)' 2>/dev/null || true)
    if [[ -n "$DANGEROUS" ]]; then
        DANGEROUS=$(printf '%s' "$DANGEROUS" | tr '\n' ' ' | tr -s ' ')
        jq -nc --arg r "Broad git add with untracked secret-pattern files present: $DANGEROUS. Use specific file paths instead of git add . or git add -A. Set SECRETS_GATE_DISABLED=1 to override." '{decision:"block",reason:$r}'
        exit 0
    fi
fi

exit 0
