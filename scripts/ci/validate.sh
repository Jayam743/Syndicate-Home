#!/usr/bin/env bash
set -euo pipefail

# Syndicate validation — run before every push
# Checks: structure, frontmatter, secrets scan, lint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ERRORS=0

echo "=== Syndicate Validation ==="
echo ""

# --- 1. Structure Check ---
echo "--- Structure ---"

REQUIRED_FILES=(
    "README.md"
    "CLAUDE.md"
    "install.sh"
    "config/models.md"
    "config/toolkit.md"
    "config/settings.template.json"
    "SYNDICATE_AXIOMS.md"
    "agents/odin.md"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${REPO_ROOT}/${f}" ]; then
        echo "  FAIL: missing required file: ${f}"
        ERRORS=$((ERRORS + 1))
    fi
done

# Every agent must have a .md file
AGENT_COUNT=$(find "${REPO_ROOT}/agents" -name "*.md" | wc -l)
if [ "$AGENT_COUNT" -lt 1 ]; then
    echo "  FAIL: no agent definitions found in agents/"
    ERRORS=$((ERRORS + 1))
else
    echo "  OK: ${AGENT_COUNT} agent definitions found"
fi

# --- 2. Frontmatter Validation ---
echo ""
echo "--- Agent Frontmatter ---"

for agent in "${REPO_ROOT}/agents/"*.md; do
    name="$(basename "$agent" .md)"

    # Check required frontmatter fields
    if ! head -20 "$agent" | grep -q "^name:"; then
        echo "  FAIL: ${name} — missing 'name:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi

    if ! head -20 "$agent" | grep -q "^model:"; then
        echo "  FAIL: ${name} — missing 'model:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi

    if ! head -20 "$agent" | grep -q "^fallback_model:"; then
        echo "  FAIL: ${name} — missing 'fallback_model:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi

    if ! head -20 "$agent" | grep -q "^tier:"; then
        echo "  FAIL: ${name} — missing 'tier:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi

    if ! head -20 "$agent" | grep -q "^description:"; then
        echo "  FAIL: ${name} — missing 'description:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "  OK: all agents have required frontmatter"
fi

# --- 3. Model Tier Validation ---
echo ""
echo "--- Model Tier Rules ---"

for agent in "${REPO_ROOT}/agents/"*.md; do
    name="$(basename "$agent" .md)"
    model=$(grep "^model:" "$agent" | head -1 | sed 's/model: *//')
    fallback=$(grep "^fallback_model:" "$agent" | head -1 | sed 's/fallback_model: *//')

    # Universal fallback rule: a fallback must stay in the SAME family
    # (opus→opus, sonnet→sonnet) OR be "session" (the universal floor for an
    # agent already at the cheapest model we'd run it on). Never cross UP a tier.
    if [ "$fallback" = "session" ]; then
        : # session is always valid — it's the universal floor
    elif echo "$model" | grep -qi "opus"; then
        if ! echo "$fallback" | grep -qi "opus"; then
            echo "  FAIL: ${name} — opus model must fallback to opus or 'session' (got: ${fallback})"
            ERRORS=$((ERRORS + 1))
        fi
    elif echo "$model" | grep -qi "sonnet"; then
        if ! echo "$fallback" | grep -qi "sonnet"; then
            echo "  FAIL: ${name} — sonnet model must fallback to sonnet or 'session' (got: ${fallback})"
            ERRORS=$((ERRORS + 1))
        fi
    elif echo "$model" | grep -qi "haiku"; then
        if ! echo "$fallback" | grep -qi "haiku"; then
            echo "  FAIL: ${name} — haiku model must fallback to haiku or 'session' (got: ${fallback})"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "  OK: all fallbacks valid (same-family or session floor)"
fi

# --- 3b. Spawn Authority (Axiom 11) ---
echo ""
echo "--- Spawn Authority (only Odin spawns) ---"

for agent in "${REPO_ROOT}/agents/"*.md; do
    name="$(basename "$agent" .md)"
    [ "$name" = "odin" ] && continue

    # Extract the tools block and check for the Agent tool
    if awk '/^tools:/{flag=1;next}/^---/{flag=0}flag' "$agent" | grep -qE '^\s*-\s*Agent\s*$'; then
        echo "  FAIL: ${name} — has the Agent tool (Axiom 11: only Odin spawns)"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "  OK: only Odin holds spawn authority"
fi

# --- 4. Secrets Scan ---
echo ""
echo "--- Secrets Scan ---"

SECRET_PATTERNS=(
    'AKIA[0-9A-Z]{16}'           # AWS Access Key
    'sk-[a-zA-Z0-9]{48}'         # OpenAI/Anthropic key pattern
    'ghp_[a-zA-Z0-9]{36}'        # GitHub PAT
    'glpat-[a-zA-Z0-9\-]{20}'    # GitLab PAT
    'xox[baprs]-[a-zA-Z0-9\-]+'  # Slack token
    'password\s*[:=]\s*["\x27][^"\x27]+'  # Hardcoded passwords
    'secret\s*[:=]\s*["\x27][^"\x27]+'    # Hardcoded secrets
)

SECRETS_FOUND=0
for pattern in "${SECRET_PATTERNS[@]}"; do
    matches=$(grep -rn -E "$pattern" "${REPO_ROOT}" --include="*.md" --include="*.sh" --include="*.yml" --include="*.yaml" --include="*.json" 2>/dev/null | grep -v ".git/" || true)
    if [ -n "$matches" ]; then
        echo "  FAIL: potential secret found matching pattern: ${pattern}"
        echo "$matches" | while read -r line; do
            echo "    ${line}"
        done
        SECRETS_FOUND=$((SECRETS_FOUND + 1))
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$SECRETS_FOUND" -eq 0 ]; then
    echo "  OK: no secrets detected"
fi

# --- 5. Markdown Lint (basic) ---
echo ""
echo "--- Markdown Lint ---"

while IFS= read -r -d '' f; do
    # Check for trailing whitespace
    if grep -qn ' $' "$f" 2>/dev/null; then
        echo "  WARN: trailing whitespace in $(basename "$f") (non-blocking)"
    fi

    # Check for tabs (prefer spaces in markdown)
    if grep -qP '^\t' "$f" 2>/dev/null; then
        echo "  WARN: tab indentation in $(basename "$f") (non-blocking)"
    fi
done < <(find "${REPO_ROOT}" -name "*.md" -not -path "*/.git/*" -print0)

echo "  OK: markdown checks passed (warnings are non-blocking)"

# --- 6. Shell Script Lint ---
echo ""
echo "--- Shell Scripts ---"

while IFS= read -r -d '' script; do
    name="$(basename "$script")"

    # Check shebang
    if ! head -1 "$script" | grep -q "^#!/"; then
        echo "  FAIL: ${name} — missing shebang"
        ERRORS=$((ERRORS + 1))
    fi

    # Check executable bit
    if [ ! -x "$script" ]; then
        echo "  FAIL: ${name} — not executable (run: chmod +x ${script})"
        ERRORS=$((ERRORS + 1))
    fi

    # Run shellcheck if available
    if command -v shellcheck &>/dev/null; then
        if ! shellcheck -S warning "$script" 2>/dev/null; then
            echo "  FAIL: ${name} — shellcheck errors"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done < <(find "${REPO_ROOT}" -name "*.sh" -not -path "*/.git/*" -print0)

if [ "$ERRORS" -eq 0 ]; then
    echo "  OK: shell scripts valid"
fi

# --- Summary ---
echo ""
echo "=========================="
if [ "$ERRORS" -gt 0 ]; then
    echo "FAILED: ${ERRORS} error(s) found"
    exit 1
else
    echo "PASSED: all checks green"
    exit 0
fi
