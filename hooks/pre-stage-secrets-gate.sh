#!/usr/bin/env bash
# Pre-stage secrets gate — blocks git add of files containing secrets
#
# Catches: .env, .key, .pem, credentials.json, .tfvars, and common
# secret patterns inside files being staged.
#
# Install: add to ~/.claude/settings.json under hooks.PreToolUse
# Matcher: "Bash(git add*)"

set -euo pipefail

# Extract the file paths from the git add command
# The full command is passed as arguments
COMMAND="$*"

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

# Check each file being added
BLOCKED_FILES=""
for pattern in "${BLOCKED_PATTERNS[@]}"; do
    # Find matching files in the command
    matches=$(echo "$COMMAND" | grep -oE "[^ ]+" | grep -E "$pattern" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        BLOCKED_FILES="${BLOCKED_FILES}${matches}\n"
    fi
done

if [ -n "$BLOCKED_FILES" ]; then
    echo "[secrets-gate] BLOCKED: Attempted to stage files matching secret patterns:"
    echo -e "$BLOCKED_FILES" | sort -u | while read -r f; do
        [ -n "$f" ] && echo "  ✗ $f"
    done
    echo ""
    echo "  If this is intentional, use 'git add --force' (not recommended)."
    echo "  Better: add the file to .gitignore and store secrets in a vault."
    exit 1
fi

# Also check for broad adds that might catch secrets
if echo "$COMMAND" | grep -qE '(git add \.|git add -A|git add --all)'; then
    # Check if any secret-patterned files exist in the working tree
    DANGEROUS=$(git ls-files --others --exclude-standard | grep -E '(\.env|\.key|\.pem|credentials|\.tfvars|secrets\.)' 2>/dev/null || true)
    if [ -n "$DANGEROUS" ]; then
        echo "[secrets-gate] WARNING: Broad 'git add' with untracked secret-pattern files:"
        echo "$DANGEROUS" | while read -r f; do
            echo "  ⚠ $f"
        done
        echo ""
        echo "  Use specific file paths instead of 'git add .' or 'git add -A'."
        exit 1
    fi
fi

exit 0
