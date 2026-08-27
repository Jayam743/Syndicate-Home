#!/usr/bin/env bash
# syndicate-activate — enable Syndicate self-dispatch for the CURRENT repo (cwd)
#
# Why per-repo: in layered mode (BJ's workflow present) Syndicate must NOT write
# its SessionStart/SessionEnd hooks into BJ's shared ~/.claude/settings.json
# (CLAUDE.md coexistence rule). Instead we activate additively via the repo's
# ./.claude/settings.local.json — Claude Code's sanctioned, git-ignored personal
# layer. This makes activation opt-in, per-repo, and reversible.
#
# Usage:
#   syndicate-activate                 remove the old global entries, THEN activate this repo
#   syndicate-activate --remove-global remove ONLY Syndicate's two entries from
#                                      ~/.claude/settings.json (cleanup of the old bug)
#
# Idempotent + shellcheck-clean. Read -> jq to tmp -> mv (never redirect into input).

set -euo pipefail

SYNDICATE_HOOKS="${HOME}/.syndicate/hooks"
SS_HOOK="${SYNDICATE_HOOKS}/session-start-syndicate.sh"
SE_HOOK="${SYNDICATE_HOOKS}/session-end-ledger.sh"

GLOBAL_SETTINGS="${HOME}/.claude/settings.json"
LOCAL_SETTINGS=".claude/settings.local.json"

# Trailing path fragments that uniquely identify Syndicate's two entries.
# basename alone is too broad; a full $HOME path is too brittle (worktrees, moves).
F1="/.syndicate/hooks/session-start-syndicate.sh"
F2="/.syndicate/hooks/session-end-ledger.sh"

MODE="activate"
case "${1:-}" in
    --remove-global) MODE="remove-global" ;;
    -h|--help)
        echo "Usage: syndicate-activate [--remove-global]"
        echo "  (default)         remove old global entries, then activate this repo (.claude/settings.local.json)"
        echo "  --remove-global   remove ONLY Syndicate's two entries from ~/.claude/settings.json"
        exit 0 ;;
    "") ;;
    *)
        echo "Unknown argument: $1" >&2
        echo "Usage: syndicate-activate [--remove-global]" >&2
        exit 1 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠  jq not found — syndicate-activate needs jq to edit settings JSON safely."
    echo "   Install jq, then re-run."
    exit 1
fi

# Two-level removal of Syndicate's entries from a settings file:
#   (a) drop an outer .hooks[$ev][] element whose inner .hooks[] are ALL ours
#   (b) for a multi-hook outer element, drop only the matching inner .hooks[]
#       and keep the matcher + any sibling (e.g. BJ's) hooks.
# Both cases fall out of: filter inner hooks, then drop the outer element iff its
# inner list became empty. Non-object / direct-command entries are left untouched.
remove_syn_entries() {
    local file="$1" tmp
    if [ ! -f "$file" ]; then
        echo "  ○ ${file} absent — nothing to remove"
        return
    fi
    tmp="$(mktemp)"
    if jq --arg f1 "$F1" --arg f2 "$F2" '
        def syn($c): ($c | type == "string") and (($c | endswith($f1)) or ($c | endswith($f2)));
        if .hooks then
          .hooks |= map_values(
            map(
              if (type == "object") and (.hooks? != null) then
                (.hooks |= map(select(syn(.command // "") | not)))
                | (if (.hooks | length) == 0 then empty else . end)
              else . end
            )
          )
        else . end
    ' "$file" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
        if cmp -s "$file" "$tmp"; then
            echo "  ○ ${file} — no Syndicate entries present"
            rm -f "$tmp"
        else
            mv "$tmp" "$file"
            echo "  ✓ removed Syndicate entries from ${file} (BJ's siblings + .permissions preserved)"
        fi
    else
        rm -f "$tmp"
        echo "  ⚠ jq transform failed — ${file} left UNCHANGED"
    fi
}

# Idempotently merge one hook entry into a settings file.
#   merge_entry <file> <event> <matcher> <command>
# Skips if a hook with this command already exists under this event.
merge_entry() {
    local file="$1" ev="$2" matcher="$3" cmd="$4" tmp
    if jq -e --arg ev "$ev" --arg c "$cmd" \
        '[(.hooks[$ev] // [])[] | (.command? // (.hooks[]?.command // empty))] | index($c)' \
        "$file" >/dev/null 2>&1; then
        echo "  ○ ${ev} → ${cmd} already present"
        return
    fi
    tmp="$(mktemp)"
    jq --arg ev "$ev" --arg m "$matcher" --arg c "$cmd" '
        .hooks[$ev] = ((.hooks[$ev] // []) + [
            ($m | if . == "" then {hooks:[{type:"command",command:$c}]}
                  else {matcher:$m, hooks:[{type:"command",command:$c}]} end)
        ])' "$file" > "$tmp" && mv "$tmp" "$file"
    echo "  ✓ ${ev} registered → ${cmd}"
}

if [ "$MODE" = "remove-global" ]; then
    echo "━━━ Removing Syndicate entries from ${GLOBAL_SETTINGS} ━━━"
    remove_syn_entries "$GLOBAL_SETTINGS"
    exit 0
fi

# --- Plain activate: cleanup global FIRST (order matters), then write per-repo ---
# If we wrote the per-repo SessionEnd while the global one still existed, the
# ledger hook would fire twice and duplicate entries. Remove-global first.
echo "━━━ Step 1/3: clean up old global entries ━━━"
remove_syn_entries "$GLOBAL_SETTINGS"
echo ""

echo "━━━ Step 2/3: activate this repo (${LOCAL_SETTINGS}) ━━━"
mkdir -p "$(dirname "$LOCAL_SETTINGS")"
[ -f "$LOCAL_SETTINGS" ] || echo '{}' > "$LOCAL_SETTINGS"
merge_entry "$LOCAL_SETTINGS" "SessionStart" "startup" "$SS_HOOK"
merge_entry "$LOCAL_SETTINGS" "SessionEnd" "" "$SE_HOOK"
echo ""

echo "━━━ Step 3/3: git-ignore ${LOCAL_SETTINGS} ━━━"
IGNORE_LINE=".claude/settings.local.json"
if git rev-parse --git-dir >/dev/null 2>&1; then
    EXCLUDE_FILE="$(git rev-parse --git-path info/exclude)"
    mkdir -p "$(dirname "$EXCLUDE_FILE")"
    touch "$EXCLUDE_FILE"
    if grep -Fxq "$IGNORE_LINE" "$EXCLUDE_FILE"; then
        echo "  ○ ${IGNORE_LINE} already git-ignored (${EXCLUDE_FILE})"
    else
        printf '%s\n' "$IGNORE_LINE" >> "$EXCLUDE_FILE"
        echo "  ✓ git-ignored ${IGNORE_LINE} via ${EXCLUDE_FILE}"
    fi
else
    echo "  ⚠ WARNING: not inside a git repo. Wrote ${LOCAL_SETTINGS} but did NOT"
    echo "    git-ignore it. If you later run 'git init' here, add this line to"
    echo "    .gitignore manually so the personal settings don't get committed:"
    echo "        ${IGNORE_LINE}"
fi
echo ""

echo "✓ Syndicate self-dispatch activated for this repo."
echo "  Fresh sessions started here will auto-load the dispatch doctrine."
