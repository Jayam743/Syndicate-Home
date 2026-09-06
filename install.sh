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

# --- 2.5. Install Scripts ---
# Skills/agents call helper scripts (recall.sh, loki-log.sh, investigation-memory.sh,
# etc.) by absolute path ~/.syndicate/scripts/ — NOT repo-relative. Reason: /retro,
# Specter, Muse, Hermes run from whatever project you're in, not the Syndicate repo,
# so a relative "scripts/foo.sh" silently fails everywhere else. Link them to a
# stable home, same pattern as hooks.
echo "━━━ Scripts ━━━"
SYNDICATE_SCRIPTS="${SYNDICATE_DIR}/scripts"
mkdir -p "$SYNDICATE_SCRIPTS"
find "${SCRIPT_DIR}/scripts" -maxdepth 1 -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
for scr in "${SCRIPT_DIR}/scripts/"*.sh; do
    [ -e "$scr" ] || continue
    sname="$(basename "$scr")"
    starget="${SYNDICATE_SCRIPTS}/${sname}"
    [ -L "$starget" ] && rm "$starget"
    ln -sf "$scr" "$starget"
done
echo "  ✓ Scripts linked to ~/.syndicate/scripts/ (recall, loki-log, investigation-memory, …)"

# User-facing per-repo activation commands. Same symlink pattern as above; called
# by name from a repo to opt that repo into Syndicate self-dispatch (layered mode).
for actscr in syndicate-activate.sh syndicate-deactivate.sh; do
    src="${SCRIPT_DIR}/scripts/${actscr}"
    [ -e "$src" ] || continue
    chmod +x "$src" 2>/dev/null || true
    tgt="${SYNDICATE_SCRIPTS}/${actscr}"
    [ -L "$tgt" ] && rm "$tgt"
    ln -sf "$src" "$tgt"
done
echo "  ✓ syndicate-activate / syndicate-deactivate linked (per-repo self-dispatch)"
echo ""

# --- 3. Install Hooks ---
echo "━━━ Hooks ━━━"

# Hooks live in the repo but are referenced from ~/.syndicate/hooks/ so that
# settings.json paths are stable regardless of where the repo is cloned.
SYNDICATE_HOOKS="${SYNDICATE_DIR}/hooks"
mkdir -p "$SYNDICATE_HOOKS"
find "${SCRIPT_DIR}/hooks" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
for hook in "${SCRIPT_DIR}/hooks/"*.sh; do
    hname="$(basename "$hook")"
    htarget="${SYNDICATE_HOOKS}/${hname}"
    [ -L "$htarget" ] && rm "$htarget"
    ln -sf "$hook" "$htarget"
done
echo "  ✓ Hooks linked to ~/.syndicate/hooks/"

# --- 3b. Git-native commit-msg gate (Decision-Review) ---
# Unlike CC hooks (referenced from ~/.syndicate/hooks via settings.json), a git
# hook MUST live at <repo>/.git/hooks/commit-msg — git invokes it there. We symlink
# it into the Syndicate repo itself (the managed repo). The hook is self-scoping
# (no-ops unless a Syndicate marker is present) and carries its own kill-switch
# (SYNDICATE_DECISION_GATE_DISABLED=1), so this is safe to install everywhere it
# applies. Idempotent; a pre-existing real hook is backed up, never clobbered.
GIT_HOOK_SRC="${SCRIPT_DIR}/hooks/git/commit-msg"
GIT_HOOKS_DIR="${SCRIPT_DIR}/.git/hooks"
if [ -f "$GIT_HOOK_SRC" ] && [ -d "$GIT_HOOKS_DIR" ]; then
    chmod +x "$GIT_HOOK_SRC" 2>/dev/null || true
    GIT_HOOK_TARGET="${GIT_HOOKS_DIR}/commit-msg"
    if [ -L "$GIT_HOOK_TARGET" ]; then
        rm "$GIT_HOOK_TARGET"
        ln -s "$GIT_HOOK_SRC" "$GIT_HOOK_TARGET"
        echo "  ✓ commit-msg gate linked → .git/hooks/commit-msg (updated)"
    elif [ -f "$GIT_HOOK_TARGET" ]; then
        mv "$GIT_HOOK_TARGET" "${GIT_HOOK_TARGET}.pre-syndicate.bak"
        ln -s "$GIT_HOOK_SRC" "$GIT_HOOK_TARGET"
        echo "  ✓ commit-msg gate linked (backed up existing → commit-msg.pre-syndicate.bak)"
    else
        ln -s "$GIT_HOOK_SRC" "$GIT_HOOK_TARGET"
        echo "  ✓ commit-msg gate linked → .git/hooks/commit-msg (new)"
    fi
else
    echo "  ○ commit-msg gate skipped (no .git/hooks/ or source missing)"
fi

SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
SS_HOOK="${SYNDICATE_HOOKS}/session-start-syndicate.sh"

# The SessionStart hook is what makes Syndicate a SELF-SYSTEM — it injects the
# dispatch doctrine so the session self-routes in ACTIVATED repos. In standalone
# mode it is registered globally in ~/.claude/settings.json; in layered mode it
# is NOT written to BJ's shared settings — instead each repo opts in per-repo via
# `syndicate-activate` (writes ./.claude/settings.local.json). Register it
# additively (never clobber existing hooks).
# Register a hook additively in Claude Code's object form:
#   { "matcher": "<m>", "hooks": [ { "type": "command", "command": "<path>" } ] }
# Matches against the nested command string so it's idempotent AND compatible
# with existing object-form entries (like BJ's workflow uses).
#   $1 = target settings file
#   $2 = event name (SessionStart / SessionEnd / ...)
#   $3 = matcher (e.g. "startup"; use "" for events that take no matcher)
#   $4 = command path
#   $5 = human label for the echo
register_hook() {
    local file="$1" event="$2" matcher="$3" cmd="$4" label="$5" tmp
    # Already present anywhere in this event's tree?
    if jq -e --arg c "$cmd" --arg ev "$event" \
        '[(.hooks[$ev] // [])[] | (.command? // (.hooks[]?.command // empty))] | index($c)' \
        "$file" >/dev/null 2>&1; then
        echo "  ○ ${label} already registered"
        return
    fi
    tmp="$(mktemp)"
    jq --arg ev "$event" --arg m "$matcher" --arg c "$cmd" '
        .hooks[$ev] = ((.hooks[$ev] // []) + [
            ($m | if . == "" then {hooks:[{type:"command",command:$c}]}
                  else {matcher:$m, hooks:[{type:"command",command:$c}]} end)
        ])' "$file" > "$tmp" && mv "$tmp" "$file"
    echo "  ✓ ${label} registered"
}

# $1 = target settings file
register_sessionstart() {
    local file="$1"
    if ! command -v jq &>/dev/null; then
        echo "  ⚠  jq not found — add these to ${file} manually (object form):"
        echo "     SessionStart(matcher=startup) → ${SS_HOOK}"
        echo "     SessionEnd → ${SYNDICATE_HOOKS}/session-end-ledger.sh"
        return
    fi
    [ -f "$file" ] || echo '{}' > "$file"

    register_hook "$file" "SessionStart" "startup" "$SS_HOOK" "SessionStart self-dispatch"
    register_hook "$file" "SessionEnd" "" "${SYNDICATE_HOOKS}/session-end-ledger.sh" "SessionEnd ledger hook"
}

if [ "$BJ_DETECTED" = true ]; then
    echo "  Layered mode: BJ's safety hooks stay. Syndicate does NOT touch"
    echo "  ~/.claude/settings.json (BJ's shared file). Enable self-dispatch"
    echo "  PER-REPO instead:"
    echo ""
    echo "      cd <your repo> && syndicate-activate"
    echo ""
    echo "  That writes ./.claude/settings.local.json (Claude Code's git-ignored"
    echo "  personal layer) and leaves BJ's settings untouched. Run it once per"
    echo "  repo where you want the crew to auto-dispatch."
    echo "  ○ Safety gates (test/secrets/prod) come from BJ's workflow"
    echo ""
    echo "  Home box: the BJ layer is NOT fetched from upstream — it comes from the"
    echo "  frozen snapshot in vendor/bj-baseline/. Install its core skills with:"
    echo "       ./scripts/install-bj-baseline.sh"
    echo "  (links the vendored BJ core skills into ~/.claude/skills/, skipping any"
    echo "   you already have)."
else
    echo "  Standalone mode: registering Syndicate's own hooks."
    register_sessionstart "$SETTINGS_FILE"
    echo "  ✓ session-start-syndicate.sh (self-dispatch doctrine injection)"
    echo "  ✓ session-end-ledger.sh (Ledger live tracking)"
    echo "  ✓ pre-push-test-gate.sh, pre-stage-secrets-gate.sh, godspeed.sh"
    echo "  ℹ  For the safety GATES (test/secrets/stop), also merge the PreToolUse/"
    echo "     PostToolUse/Stop blocks from config/settings.template.json into ${SETTINGS_FILE}"
    echo "  ℹ  If you want BJ's core skills too, run: ./scripts/install-bj-baseline.sh"
fi
echo ""

# --- 4. Create Ledger tracking directories ---
echo "━━━ Ledger (live tracking) ━━━"
mkdir -p "${SYNDICATE_DIR}/ledger/archive"
mkdir -p "${SYNDICATE_DIR}/ledger/monthly"
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

# --- 5. Create Loki logs & pipeline dirs ---
echo "━━━ Loki + Pipelines ━━━"
mkdir -p "${SCRIPT_DIR}/loki/logs"
mkdir -p "${SYNDICATE_DIR}/loki"
mkdir -p "${SYNDICATE_DIR}/pipelines"
mkdir -p "${SYNDICATE_DIR}/conception"
mkdir -p "${SYNDICATE_DIR}/investigations"
echo "  ✓ ~/.syndicate/loki/ (live improvement findings — auto-logged by /retro)"
echo "  ✓ loki/logs/ (committed monthly archive — synced by /loki-review)"
echo "  ✓ ~/.syndicate/pipelines/ (pipeline state persistence)"
echo "  ✓ ~/.syndicate/conception/ (Muse decision ledgers)"
echo "  ✓ ~/.syndicate/investigations/ (Specter flight logs)"
echo ""

# --- 6. Dependency probes (home: subscription — no Bedrock/aws/glab) ---
echo "━━━ Dependencies ━━━"

# jq is HARD — the installer's hook registration and several hooks require it.
if command -v jq &>/dev/null; then
    echo "  ✓ jq: installed"
else
    echo "  ✗ jq: NOT FOUND (required) — install jq before continuing"
    echo "    (hook registration + several Syndicate hooks depend on it)"
fi

# markitdown / shellcheck / gh are SOFT — warn, don't block.
if command -v markitdown &>/dev/null; then
    echo "  ✓ markitdown: installed"
else
    echo "  ○ markitdown: not found (optional — needed for Cipher agent)"
    echo "    Install: pip install markitdown"
fi

if command -v shellcheck &>/dev/null; then
    echo "  ✓ shellcheck: installed"
else
    echo "  ○ shellcheck: not found (optional, for validate.sh)"
fi

if command -v gh &>/dev/null; then
    echo "  ✓ gh: installed (GitHub CLI)"
else
    echo "  ○ gh: not found (optional — install for PR workflows; home is GitHub-only)"
fi

# NOTE: on a subscription the harness resolves the opus/sonnet/haiku aliases itself —
# this installer does NOT set any model/Bedrock/AWS env vars.
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
echo "  ~/.syndicate/        ← Ledger tracking + model audit"
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
