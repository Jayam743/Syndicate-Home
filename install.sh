#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
AGENTS_DIR="${CLAUDE_DIR}/agents"
SKILLS_DIR="${CLAUDE_DIR}/skills"
SYNDICATE_DIR="${HOME}/.syndicate"

echo "=== Syndicate Installer ==="
echo ""
echo "This installs Syndicate agents alongside your existing CC workflow."
echo "It does NOT touch your skills, hooks, or settings."
echo ""

# Ensure target dirs exist
mkdir -p "${AGENTS_DIR}"
mkdir -p "${SKILLS_DIR}"

# Install agents (symlink so edits propagate)
echo "--- Agents ---"
for agent in "${SCRIPT_DIR}/agents/"*.md; do
    name="$(basename "$agent")"
    target="${AGENTS_DIR}/${name}"
    if [ -L "$target" ] || [ -f "$target" ]; then
        rm "$target"
    fi
    ln -s "$agent" "$target"
    echo "  Linked: ${name}"
done

# Install skills (symlink directories — only Syndicate-specific skills)
echo ""
echo "--- Skills (Syndicate-only, won't overwrite existing) ---"
if [ -d "${SCRIPT_DIR}/skills" ] && [ "$(ls -A "${SCRIPT_DIR}/skills" 2>/dev/null)" ]; then
    for skill_dir in "${SCRIPT_DIR}/skills/"*/; do
        if [ -d "$skill_dir" ]; then
            name="$(basename "$skill_dir")"
            target="${SKILLS_DIR}/${name}"
            # Don't overwrite existing skills from BJ's workflow
            if [ -d "$target" ] && [ ! -L "$target" ]; then
                echo "  SKIP: ${name}/ (existing skill, not overwriting)"
            else
                if [ -L "$target" ]; then
                    rm "$target"
                fi
                ln -s "$skill_dir" "$target"
                echo "  Linked: ${name}/"
            fi
        fi
    done
else
    echo "  (no skills yet)"
fi

# Create Ledger tracking directories
echo ""
echo "--- Ledger (live tracking) ---"
mkdir -p "${SYNDICATE_DIR}/ledger/archive"
mkdir -p "${SYNDICATE_DIR}/ledger/monthly"
if [ ! -f "${SYNDICATE_DIR}/ledger/current-week.md" ]; then
    cat > "${SYNDICATE_DIR}/ledger/current-week.md" << 'EOF'
# Week: (auto-filled on first entry)

## Work Items
(Ledger will populate this as you work)
EOF
    echo "  Created: current-week.md"
else
    echo "  Exists: current-week.md (not overwriting)"
fi

# Create Loki logs dir
echo ""
echo "--- Loki (improvement logs) ---"
mkdir -p "${SCRIPT_DIR}/loki/logs"
echo "  Ready: loki/logs/"

# Install markitdown if not present
echo ""
echo "--- Dependencies ---"
if command -v markitdown &>/dev/null; then
    echo "  markitdown: already installed"
else
    echo "  markitdown: installing via pip..."
    pip install markitdown 2>/dev/null || pip3 install markitdown 2>/dev/null || echo "  WARNING: could not install markitdown (install manually: pip install markitdown)"
fi

# Summary
echo ""
echo "=== Syndicate installed ==="
echo ""
echo "What was installed:"
echo "  ~/.claude/agents/   ← Syndicate agent definitions (symlinked)"
echo "  ~/.syndicate/       ← Ledger tracking data"
echo ""
echo "What was NOT touched:"
echo "  ~/.claude/skills/   ← Your existing skills (engage, precheck, etc.)"
echo "  ~/.claude/settings.json ← Your hooks and permissions"
echo "  Any project CLAUDE.md"
echo ""
echo "Try it: start a Claude Code session and say 'Route this to Forge: write hello world in Python'"
