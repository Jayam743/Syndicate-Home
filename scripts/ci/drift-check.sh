#!/usr/bin/env bash
set -euo pipefail

# Drift check — verify installed agents match the repo
# Run this to detect if someone edited ~/.claude/agents/ directly
# or if install.sh needs to be re-run after pulling changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AGENTS_DIR="${HOME}/.claude/agents"
DRIFT=0

echo "=== Syndicate Drift Check ==="
echo ""

if [ ! -d "$AGENTS_DIR" ]; then
    echo "DRIFT: ~/.claude/agents/ does not exist — run ./install.sh"
    exit 1
fi

echo "--- Checking agent symlinks ---"

# Check each repo agent has a matching symlink
while IFS= read -r -d '' agent; do
    name="$(basename "$agent")"
    target="${AGENTS_DIR}/${name}"

    if [ ! -e "$target" ]; then
        echo "  MISSING: ${name} — not installed (run ./install.sh)"
        DRIFT=$((DRIFT + 1))
    elif [ -L "$target" ]; then
        link_target="$(readlink -f "$target")"
        repo_path="$(readlink -f "$agent")"
        if [ "$link_target" != "$repo_path" ]; then
            echo "  DRIFT: ${name} — symlink points to wrong location"
            echo "    Expected: ${repo_path}"
            echo "    Actual:   ${link_target}"
            DRIFT=$((DRIFT + 1))
        fi
    else
        echo "  DRIFT: ${name} — is a file, not a symlink (manual edit detected)"
        DRIFT=$((DRIFT + 1))
    fi
done < <(find "${REPO_ROOT}/agents" -name "*.md" -print0)

# Check for extra agents in ~/.claude/agents/ that aren't in repo
echo ""
echo "--- Checking for orphaned agents ---"

while IFS= read -r -d '' installed; do
    name="$(basename "$installed")"
    if [ ! -f "${REPO_ROOT}/agents/${name}" ]; then
        echo "  ORPHAN: ${name} — exists in ~/.claude/agents/ but not in repo"
        echo "    (This is fine if it's from another source like a plugin)"
    fi
done < <(find "${AGENTS_DIR}" -maxdepth 1 -name "*.md" -print0 2>/dev/null)

# --- Frontmatter model: drift detection ---
echo ""
echo "--- Checking frontmatter model: drift ---"

while IFS= read -r -d '' agent; do
    name="$(basename "$agent")"
    installed="${AGENTS_DIR}/${name}"

    # Only check if the installed copy exists and is readable
    [ -f "$installed" ] || continue

    repo_model="$(grep "^model:" "$agent" | head -1 | sed 's/model: *//')"
    installed_model="$(grep "^model:" "$installed" | head -1 | sed 's/model: *//')"

    if [ -n "$repo_model" ] && [ -n "$installed_model" ] && [ "$repo_model" != "$installed_model" ]; then
        echo "  WARN: ${name} — installed model differs from repo"
        echo "    Repo:      ${repo_model}"
        echo "    Installed: ${installed_model}"
    fi
done < <(find "${REPO_ROOT}/agents" -name "*.md" -print0)

# Summary
echo ""
echo "=========================="
if [ "$DRIFT" -gt 0 ]; then
    echo "DRIFT DETECTED: ${DRIFT} agent(s) out of sync"
    echo "Run: ./install.sh to reconcile"
    exit 1
else
    echo "NO DRIFT: all agents in sync with repo"
    exit 0
fi
