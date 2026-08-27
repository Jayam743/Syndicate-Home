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

# --- 3. Pinned-Set and Tier Band Validation ---
echo ""
echo "--- Pinned-Set + Tier Band Rules ---"

# The 4 pinned model IDs (Bedrock hard limit)
PINNED_MODELS=(
    "us.anthropic.claude-opus-4-8"
    "us.anthropic.claude-opus-4-7"
    "us.anthropic.claude-sonnet-4-6"
    "us.anthropic.claude-haiku-4-5-20251001-v1:0"
)

# Valid tier bands
VALID_TIERS=("think" "formula" "mechanical")

is_pinned_model() {
    local val="$1"
    for pinned in "${PINNED_MODELS[@]}"; do
        if [ "$val" = "$pinned" ]; then
            return 0
        fi
    done
    return 1
}

is_valid_tier() {
    local val="$1"
    for tier in "${VALID_TIERS[@]}"; do
        if [ "$val" = "$tier" ]; then
            return 0
        fi
    done
    return 1
}

for agent in "${REPO_ROOT}/agents/"*.md; do
    name="$(basename "$agent" .md)"
    model=$(grep "^model:" "$agent" | head -1 | sed 's/model: *//')
    fallback=$(grep "^fallback_model:" "$agent" | head -1 | sed 's/fallback_model: *//')
    tier=$(grep "^tier:" "$agent" | head -1 | sed 's/tier: *//')

    # model: must be one of the 4 pinned IDs
    if ! is_pinned_model "$model"; then
        echo "  FAIL: ${name} — model '${model}' is not in the pinned set"
        ERRORS=$((ERRORS + 1))
    fi

    # fallback_model: must be one of the 4 pinned IDs OR literal 'session'
    if [ "$fallback" != "session" ] && ! is_pinned_model "$fallback"; then
        echo "  FAIL: ${name} — fallback_model '${fallback}' is not in the pinned set and is not 'session'"
        ERRORS=$((ERRORS + 1))
    fi

    # tier: must be one of {think, formula, mechanical}
    if ! is_valid_tier "$tier"; then
        echo "  FAIL: ${name} — tier '${tier}' is not a valid band (must be think|formula|mechanical)"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    echo "  OK: all models in pinned set, all tiers valid bands"
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

# --- 3c. Workflow Recall/Scribe Preconditions (issue #4) ---
# Deterministic preconditions for the heavy workflows. Anchor on the STAGE/NO-*
# COMMENTS, never on label strings — a label like 'scribe:recraft' is not a
# declaration that the stage's precondition was consciously handled.
echo ""
echo "--- Workflow Recall/Scribe Preconditions ---"

WF_ERRORS_BEFORE="$ERRORS"
if [ -d "${REPO_ROOT}/workflows" ]; then
    shopt -s nullglob
    for wf in "${REPO_ROOT}/workflows/"*.js; do
        wfname="$(basename "$wf")"

        # Scribe: an explicit '// STAGE: scribe' anchor OR a reasoned opt-out marker.
        if ! grep -Eq '^[[:space:]]*//[[:space:]]*STAGE:[[:space:]]*scribe([[:space:]]|$)' "$wf" \
           && ! grep -Eq '//[[:space:]]*SYNDICATE-NO-SCRIBE:[[:space:]]*\S' "$wf"; then
            echo "  FAIL: ${wfname} — no '// STAGE: scribe' anchor and no '// SYNDICATE-NO-SCRIBE: <reason>' opt-out"
            ERRORS=$((ERRORS + 1))
        fi

        # Recall: an explicit '// STAGE: recall' anchor OR a reasoned opt-out marker.
        if ! grep -Eq '^[[:space:]]*//[[:space:]]*STAGE:[[:space:]]*recall([[:space:]]|$)' "$wf" \
           && ! grep -Eq '//[[:space:]]*SYNDICATE-NO-RECALL:[[:space:]]*\S' "$wf"; then
            echo "  FAIL: ${wfname} — no '// STAGE: recall' anchor and no '// SYNDICATE-NO-RECALL: <reason>' opt-out"
            ERRORS=$((ERRORS + 1))
        fi

        # Skip flags must be paired with their reason arg (deterministic gate).
        if grep -q 'skipScribe' "$wf" && ! grep -q 'skipScribeReason' "$wf"; then
            echo "  FAIL: ${wfname} — references skipScribe but never skipScribeReason"
            ERRORS=$((ERRORS + 1))
        fi
        if grep -q 'skipRecall' "$wf" && ! grep -q 'skipRecallReason' "$wf"; then
            echo "  FAIL: ${wfname} — references skipRecall but never skipRecallReason"
            ERRORS=$((ERRORS + 1))
        fi
    done
    shopt -u nullglob
fi

if [ "$ERRORS" -eq "$WF_ERRORS_BEFORE" ]; then
    echo "  OK: all workflows declare scribe + recall preconditions"
fi

# --- 3d. Workflow model: Literals must be pinned ids (issue #13) ---
# Any `model:` assigned a string literal in workflows/*.js MUST be one of the 4
# pinned Bedrock ids. This closes the 400-on-unpinned-id door at CI: an unpinned
# id (e.g. a dropped [1m] variant) would fail the Bedrock call at runtime.
# Band-name / agentType refs (model: BAND.sonnet) carry no literal and are skipped.
echo ""
echo "--- Workflow model: Literals (pinned-id only) ---"

MODEL_ERRORS_BEFORE="$ERRORS"
if [ -d "${REPO_ROOT}/workflows" ]; then
    shopt -s nullglob
    for wf in "${REPO_ROOT}/workflows/"*.js; do
        wfname="$(basename "$wf")"
        while IFS= read -r val; do
            [ -z "$val" ] && continue
            if ! is_pinned_model "$val"; then
                echo "  FAIL: ${wfname} — model literal '${val}' is not in the pinned set"
                ERRORS=$((ERRORS + 1))
            fi
        done < <(grep -oE "model:[[:space:]]*['\"][^'\"]+['\"]" "$wf" | sed -E "s/model:[[:space:]]*['\"]//; s/['\"]$//")
    done
    shopt -u nullglob
fi

if [ "$ERRORS" -eq "$MODEL_ERRORS_BEFORE" ]; then
    echo "  OK: all workflow model: literals are pinned ids"
fi

# --- 3e. Inlined fan-eligibility Drift Guard (issue #8) ---
# campaign.js runs in a sandbox with no require/fs, so the tested fan-eligibility
# predicate is INLINED there byte-for-byte. This guard proves the inlined copy has
# not drifted from the canonical source: it compares the CODE of the inlined block
# (comments + blank lines + indentation stripped) against the canonical function
# region in scripts/lib/fan-eligibility.js. Any logic drift fails CI.
echo ""
echo "--- Inlined fan-eligibility Drift Guard ---"

CAMPAIGN_JS="${REPO_ROOT}/workflows/campaign.js"
FE_LIB="${REPO_ROOT}/scripts/lib/fan-eligibility.js"

fe_norm() {
    # Normalize to CODE only so cosmetic differences don't false-trip the guard.
    # Applied identically to BOTH copies, so it can only neutralize comment/format
    # differences — any real logic drift still fails. Order: strip trailing inline
    # `// ...` comments, then leading/trailing whitespace, then full-line comments
    # and blank lines.
    sed -E 's@[[:space:]]+//.*$@@; s/^[[:space:]]+//; s/[[:space:]]+$//' | grep -vE '^//' | grep -vE '^$' || true
}

if [ ! -f "$CAMPAIGN_JS" ] || [ ! -f "$FE_LIB" ]; then
    echo "  SKIP: campaign.js or fan-eligibility.js not present"
elif ! grep -q "BEGIN inlined fan-eligibility" "$CAMPAIGN_JS"; then
    echo "  FAIL: campaign.js has no inlined fan-eligibility block (BEGIN marker missing)"
    ERRORS=$((ERRORS + 1))
else
    inlined_code="$(awk '/BEGIN inlined fan-eligibility/{f=1;next} /END inlined fan-eligibility/{f=0} f' "$CAMPAIGN_JS" | fe_norm)"
    canon_code="$(awk '/const GLOB_CHARS_RE/{f=1} /^module\.exports/{f=0} f' "$FE_LIB" | fe_norm)"

    if [ "$inlined_code" = "$canon_code" ]; then
        echo "  OK: inlined fan-eligibility matches scripts/lib/fan-eligibility.js"
    else
        echo "  FAIL: inlined fan-eligibility in campaign.js has DRIFTED from scripts/lib/fan-eligibility.js"
        diff <(printf '%s\n' "$canon_code") <(printf '%s\n' "$inlined_code") | head -40 || true
        ERRORS=$((ERRORS + 1))
    fi
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

# --- 7. Script Tests ---
echo ""
echo "--- Script Tests ---"

if bash "${SCRIPT_DIR}/test.sh"; then
    echo "  OK: all script tests passed"
else
    echo "  FAIL: script tests failed"
    ERRORS=$((ERRORS + 1))
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
