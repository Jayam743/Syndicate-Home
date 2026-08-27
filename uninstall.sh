#!/usr/bin/env bash
set -uo pipefail

# ══════════════════════════════════════════════════════════════════
# Syndicate Uninstaller
#
# Removes ONLY what Syndicate installed. Preserves everything that was
# already there — BJ's workflow, your own agents/skills, and (by default)
# your history and ledger.
#
# Reversal targets:
#   1. Agent symlinks in ~/.claude/agents/ (only ones pointing at this repo)
#   2. Skill symlinks in ~/.claude/skills/ (only ones pointing at this repo)
#   3. settings.json hooks (ONLY entries pointing at ~/.syndicate/hooks/)
#   4. ~/.syndicate/hooks/ symlinks
#
# PRESERVED by default (your data — "old things stay"):
#   - ~/.syndicate/ledger/       (your activity log)
#   - ~/.syndicate/evidence/     (legacy evidence dir, no longer written)
#   - ~/.syndicate/conception/   (Muse decision ledgers)
#   - ~/.syndicate/investigations/
#   - ~/.claude/projects/        (your session history — NEVER touched)
#
# Use --purge to also remove ~/.syndicate data dirs (asks first).
# ══════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
AGENTS_DIR="${CLAUDE_DIR}/agents"
SKILLS_DIR="${CLAUDE_DIR}/skills"
SYNDICATE_DIR="${HOME}/.syndicate"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
PURGE=false

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=true ;;
        -h|--help)
            echo "Usage: ./uninstall.sh [--purge]"
            echo "  (default)  remove Syndicate agents/skills/hooks; KEEP your data + history"
            echo "  --purge    ALSO remove ~/.syndicate data dirs (ledger/pipelines/etc) — asks first"
            exit 0 ;;
    esac
done

echo "╔══════════════════════════════════════════════╗"
echo "║          SYNDICATE UNINSTALLER               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "This removes ONLY Syndicate. It preserves:"
echo "  • BJ's workflow (if present) — untouched"
echo "  • Your session history (~/.claude/projects/) — NEVER touched"
echo "  • Your ledger data (unless --purge)"
echo ""

# --- 1. Remove agent symlinks that point at THIS repo ---
echo "━━━ Agents ━━━"
removed=0
if [ -d "$AGENTS_DIR" ]; then
    for link in "${AGENTS_DIR}"/*.md; do
        [ -e "$link" ] || continue
        if [ -L "$link" ]; then
            target="$(readlink -f "$link" 2>/dev/null || echo "")"
            case "$target" in
                "${SCRIPT_DIR}/agents/"*)
                    rm "$link"; echo "  ✓ removed $(basename "$link")"; removed=$((removed+1)) ;;
            esac
        fi
    done
fi
[ "$removed" -eq 0 ] && echo "  ○ no Syndicate agent links found"
echo ""

# --- 2. Remove skill symlinks that point at THIS repo ---
echo "━━━ Skills ━━━"
removed=0
if [ -d "$SKILLS_DIR" ]; then
    for link in "${SKILLS_DIR}"/*; do
        [ -e "$link" ] || [ -L "$link" ] || continue
        if [ -L "$link" ]; then
            target="$(readlink -f "$link" 2>/dev/null || echo "")"
            case "$target" in
                "${SCRIPT_DIR}/skills/"*)
                    rm "$link"; echo "  ✓ removed $(basename "$link")/"; removed=$((removed+1)) ;;
            esac
        fi
    done
fi
[ "$removed" -eq 0 ] && echo "  ○ no Syndicate skill links found"
echo ""

# --- 3. Surgically remove OUR hooks from settings.json ---
echo "━━━ settings.json hooks ━━━"
if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &>/dev/null; then
        # Back up first (timestamped)
        BACKUP="${SETTINGS_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP"
        echo "  ℹ backup: ${BACKUP}"

        # Remove ONLY hook entries whose command references ~/.syndicate/hooks/
        # Handles both flat-string entries and object-form {matcher,hooks:[{command}]}.
        # An object-form entry is dropped only if ALL its inner hooks are ours.
        tmp="$(mktemp)"
        jq '
          def is_ours(s): (s | test("\\.syndicate/hooks/"));
          if .hooks then
            .hooks |= with_entries(
              .value |= (
                map(
                  if type == "string" then
                    (if is_ours(.) then empty else . end)
                  elif type == "object" and (.command? != null) then
                    (if is_ours(.command) then empty else . end)
                  elif type == "object" and (.hooks? != null) then
                    .hooks |= map(select((.command? // "") | is_ours(.) | not))
                    | (if (.hooks | length) == 0 then empty else . end)
                  else . end
                )
              )
            )
          else . end
        ' "$SETTINGS_FILE" > "$tmp" 2>/dev/null

        if [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
            mv "$tmp" "$SETTINGS_FILE"
            echo "  ✓ removed Syndicate hook entries (BJ's + your own hooks preserved)"
        else
            rm -f "$tmp"
            echo "  ⚠ jq transform failed — settings.json left UNCHANGED (backup kept)"
        fi
    else
        echo "  ⚠ jq not found — remove ~/.syndicate/hooks/ entries from ${SETTINGS_FILE} manually"
    fi
else
    echo "  ○ no settings.json"
fi
echo ""

# --- 3b. Warn about per-repo activation (layered mode) ---
echo "━━━ Per-repo activation ━━━"
echo "  ⚠ Repos activated with 'syndicate-activate' have Syndicate entries in their"
echo "    own ./.claude/settings.local.json. Those persist across all N repos after"
echo "    uninstall and will point at now-dead ~/.syndicate/hooks/ paths."
echo "    This uninstaller does NOT scan the filesystem for them (safety)."
echo "    In each such repo, clean up with:"
echo "        cd <repo> && syndicate-deactivate"
echo ""

# --- 4. Remove the hooks symlink dir ---
echo "━━━ ~/.syndicate/hooks ━━━"
if [ -d "${SYNDICATE_DIR}/hooks" ]; then
    rm -rf "${SYNDICATE_DIR}/hooks"
    echo "  ✓ removed ~/.syndicate/hooks/ (symlinks only)"
else
    echo "  ○ not present"
fi
echo ""

# --- 5. Data dirs (preserved unless --purge) ---
echo "━━━ Your data ━━━"
if [ "$PURGE" = true ]; then
    echo "  --purge requested. This will DELETE:"
    echo "    ${SYNDICATE_DIR}/ledger/       (activity log)"
    echo "    ${SYNDICATE_DIR}/evidence/     (legacy evidence dir, no longer written)"
    echo "    ${SYNDICATE_DIR}/conception/   (Muse ledgers)"
    echo "    ${SYNDICATE_DIR}/investigations/"
    echo "    ${SYNDICATE_DIR}/pipelines/"
    echo ""
    printf "  Type 'yes' to confirm data deletion: "
    read -r confirm
    if [ "$confirm" = "yes" ]; then
        rm -rf "${SYNDICATE_DIR}/ledger" "${SYNDICATE_DIR}/evidence" \
               "${SYNDICATE_DIR}/conception" "${SYNDICATE_DIR}/investigations" \
               "${SYNDICATE_DIR}/pipelines"
        rm -f "${SYNDICATE_DIR}/.godspeed" "${SYNDICATE_DIR}/.godspeed-state" \
              "${SYNDICATE_DIR}/.test-sentinel" "${SYNDICATE_DIR}/.installed"
        # Per-worktree sentinels (B′, issue #30); legacy .test-sentinel above
        # kept for back-compat with pre-#30 installs.
        rm -rf "${SYNDICATE_DIR}/sentinels"
        # Remove ~/.syndicate entirely if now empty
        rmdir "${SYNDICATE_DIR}" 2>/dev/null && echo "  ✓ removed ~/.syndicate/ entirely" \
            || echo "  ✓ removed Syndicate data (dir kept — had other contents)"
    else
        echo "  ○ cancelled — data preserved"
    fi
else
    echo "  ○ PRESERVED (your ledger, conception ledgers, history)"
    echo "    Your session history in ~/.claude/projects/ was never touched."
    echo "    (Run with --purge to remove Syndicate data too.)"
fi
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║            UNINSTALL COMPLETE                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Removed: Syndicate agents, skills, hooks, and settings.json entries."
echo "Kept:    BJ's workflow, your history, and (unless --purge) your data."
echo ""
echo "The repo at ${SCRIPT_DIR} is still here — delete it manually if you want it gone."
echo "To reinstall later: ./install.sh"
