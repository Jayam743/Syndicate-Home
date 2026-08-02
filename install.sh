#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
AGENTS_DIR="${CLAUDE_DIR}/agents"
SKILLS_DIR="${CLAUDE_DIR}/skills"
SYNDICATE_DIR="${HOME}/.syndicate"
BJ_WORKFLOW_MARKER="${SKILLS_DIR}/engage/SKILL.md"
INSTALLED_STAMP="${SYNDICATE_DIR}/.installed"

echo "╔══════════════════════════════════════════════╗"
echo "║         SYNDICATE INSTALLER v2.0             ║"
echo "║  Multi-agent orchestration for Claude Code   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# --- Detect BJ's workflow ---
BJ_DETECTED=false
if [ -f "$BJ_WORKFLOW_MARKER" ]; then
    BJ_DETECTED=true
    echo "✓ BJ's CC Workflow detected — layering Syndicate on top"
    echo "  (Skills, hooks, settings from BJ's workflow will NOT be overwritten)"
    echo ""
else
    echo "○ BJ's CC Workflow not detected — installing Syndicate standalone"
    echo "  (Will install Syndicate's own hooks and safety scripts)"
    echo ""
fi

# Ensure target dirs exist
mkdir -p "${AGENTS_DIR}"
mkdir -p "${SKILLS_DIR}"
mkdir -p "${SYNDICATE_DIR}"

# --- 1. Install Agents (always — these are Syndicate's own) ---
echo "━━━ Agents ━━━"
for agent in "${SCRIPT_DIR}/agents/"*.md; do
    name="$(basename "$agent")"
    target="${AGENTS_DIR}/${name}"
    if [ -L "$target" ] || [ -f "$target" ]; then
        rm "$target"
    fi
    ln -s "$agent" "$target"
    echo "  ✓ ${name}"
done
echo ""

# --- 2. Install Skills ---
echo "━━━ Skills ━━━"
if [ -d "${SCRIPT_DIR}/skills" ] && [ "$(ls -A "${SCRIPT_DIR}/skills" 2>/dev/null)" ]; then
    for skill_dir in "${SCRIPT_DIR}/skills/"*/; do
        if [ -d "$skill_dir" ]; then
            name="$(basename "$skill_dir")"
            target="${SKILLS_DIR}/${name}"

            # Don't overwrite existing skills from BJ's workflow
            if [ -d "$target" ] && [ ! -L "$target" ]; then
                echo "  ○ SKIP: ${name}/ (BJ's workflow owns this)"
            elif [ -L "$target" ]; then
                # Re-link our own symlinked skills
                link_source="$(readlink -f "$target" 2>/dev/null || echo "")"
                if [[ "$link_source" == *"Syndicate"* ]]; then
                    rm "$target"
                    ln -s "$skill_dir" "$target"
                    echo "  ✓ ${name}/ (updated)"
                else
                    echo "  ○ SKIP: ${name}/ (owned by another source)"
                fi
            else
                ln -s "$skill_dir" "$target"
                echo "  ✓ ${name}/ (new)"
            fi
        fi
    done
else
    echo "  (no skills to install)"
fi
echo ""

# --- 3. Install Hooks (only if BJ's workflow is NOT present) ---
echo "━━━ Hooks ━━━"
if [ "$BJ_DETECTED" = true ]; then
    echo "  ○ SKIP: BJ's workflow provides hooks — using those"
    echo "  ○ Syndicate's session-end-ledger.sh is additive (check settings.json)"

    # Just ensure the ledger hook is registered if not already
    SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
    if [ -f "$SETTINGS_FILE" ]; then
        if ! grep -q "session-end-ledger" "$SETTINGS_FILE" 2>/dev/null; then
            echo "  ℹ  NOTE: Add session-end-ledger.sh to your settings.json SessionEnd hooks"
            echo "     Path: ${SCRIPT_DIR}/hooks/session-end-ledger.sh"
        fi
    fi
else
    # Standalone mode: install Syndicate's own safety hooks
    echo "  Installing Syndicate safety hooks..."
    HOOKS_DIR="${SCRIPT_DIR}/hooks"
    mkdir -p "$HOOKS_DIR"

    # Make hooks executable
    find "$HOOKS_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

    echo "  ✓ session-end-ledger.sh (Ledger live tracking)"

    if [ -f "${HOOKS_DIR}/pre-push-test-gate.sh" ]; then
        echo "  ✓ pre-push-test-gate.sh (blocks push without tests)"
    fi
    if [ -f "${HOOKS_DIR}/pre-stage-secrets-gate.sh" ]; then
        echo "  ✓ pre-stage-secrets-gate.sh (blocks staging secrets)"
    fi
    if [ -f "${HOOKS_DIR}/godspeed.sh" ]; then
        echo "  ✓ godspeed.sh (autonomy mandate system)"
    fi

    echo ""
    echo "  ⚠  You need to add these hooks to ~/.claude/settings.json manually."
    echo "     See: config/settings.template.json for the full configuration."
fi
echo ""

# --- 4. Create Ledger tracking directories ---
echo "━━━ Ledger (live tracking) ━━━"
mkdir -p "${SYNDICATE_DIR}/ledger/archive"
mkdir -p "${SYNDICATE_DIR}/ledger/monthly"
mkdir -p "${SYNDICATE_DIR}/evidence"
if [ ! -f "${SYNDICATE_DIR}/ledger/current-week.md" ]; then
    cat > "${SYNDICATE_DIR}/ledger/current-week.md" << 'EOF'
# Week: (auto-filled on first entry)

## Work Items
(Ledger will populate this as you work)
EOF
    echo "  ✓ Created: current-week.md"
else
    echo "  ○ Exists: current-week.md (preserved)"
fi
echo ""

# --- 5. Create Loki logs & evidence dirs ---
echo "━━━ Loki + Evidence ━━━"
mkdir -p "${SCRIPT_DIR}/loki/logs"
mkdir -p "${SYNDICATE_DIR}/evidence"
mkdir -p "${SYNDICATE_DIR}/pipelines"
mkdir -p "${SYNDICATE_DIR}/conception"
mkdir -p "${SYNDICATE_DIR}/investigations"
echo "  ✓ loki/logs/ (improvement observations)"
echo "  ✓ ~/.syndicate/evidence/ (pipeline evidence packets)"
echo "  ✓ ~/.syndicate/pipelines/ (pipeline state persistence)"
echo "  ✓ ~/.syndicate/conception/ (Muse decision ledgers)"
echo "  ✓ ~/.syndicate/investigations/ (Specter flight logs)"
echo ""

# --- 6. Install markitdown (for Cipher) ---
echo "━━━ Dependencies ━━━"
if command -v markitdown &>/dev/null; then
    echo "  ✓ markitdown: installed"
else
    echo "  ○ markitdown: not found"
    echo "    Install: pip install markitdown (needed for Cipher agent)"
fi

if command -v shellcheck &>/dev/null; then
    echo "  ✓ shellcheck: installed"
else
    echo "  ○ shellcheck: not found (optional, for validate.sh)"
fi

if command -v gh &>/dev/null; then
    echo "  ✓ gh: installed (GitHub CLI)"
elif command -v glab &>/dev/null; then
    echo "  ✓ glab: installed (GitLab CLI)"
else
    echo "  ○ gh/glab: not found (install one for PR/MR workflows)"
fi
echo ""

# --- 7. Settings template (standalone only) ---
if [ "$BJ_DETECTED" = false ]; then
    if [ ! -f "${CLAUDE_DIR}/settings.json" ]; then
        echo "━━━ Settings ━━━"
        echo "  No settings.json found. Creating from Syndicate template..."
        if [ -f "${SCRIPT_DIR}/config/settings.template.json" ]; then
            cp "${SCRIPT_DIR}/config/settings.template.json" "${CLAUDE_DIR}/settings.json"
            echo "  ✓ Created: ~/.claude/settings.json"
        else
            echo "  ⚠  Template not found. Using minimal settings."
            cat > "${CLAUDE_DIR}/settings.json" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git branch*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git remote*)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(ls *)",
      "Bash(wc *)"
    ],
    "deny": []
  }
}
EOF
            echo "  ✓ Created: ~/.claude/settings.json (minimal)"
        fi
        echo ""
    fi
fi

# --- 8. Write install stamp ---
echo "$(date -Iseconds)" > "$INSTALLED_STAMP"
echo "$BJ_DETECTED" >> "$INSTALLED_STAMP"

# --- Summary ---
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║            INSTALLATION COMPLETE             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Installed:"
echo "  ~/.claude/agents/    ← Syndicate agents (13 specialists)"
echo "  ~/.syndicate/        ← Ledger tracking + evidence packets"
echo ""
if [ "$BJ_DETECTED" = true ]; then
    echo "Coexistence mode: BJ's workflow owns hooks + skills."
    echo "Syndicate layers agents + orchestration on top."
else
    echo "Standalone mode: Syndicate provides its own safety hooks."
    echo "See config/settings.template.json for full hook setup."
fi
echo ""
echo "Quick start:"
echo "  Say: 'Route to Forge: write a hello world in Python'"
echo "  Or:  '/route fix the login bug'"
echo "  Or:  'godspeed — implement the user profile feature'"
echo ""
echo "Agents know their toolkit. They'll use /precheck, /scp, /wtf,"
echo "and all available skills automatically."
