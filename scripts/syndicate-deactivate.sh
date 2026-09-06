#!/usr/bin/env bash
# syndicate-deactivate — disable Syndicate self-dispatch for the CURRENT repo (cwd)
#
# Removes ONLY Syndicate's two entries (SessionStart self-dispatch + SessionEnd
# ledger) from this repo's ./.claude/settings.local.json, using the same
# two-level filter as `syndicate-activate --remove-global`. Any sibling hooks
# and other keys (.permissions, etc.) are preserved. Idempotent; no-op if the
# file or the entries are absent.
#
# Read -> jq to tmp -> mv (never redirect into the input file). shellcheck-clean.

set -euo pipefail

LOCAL_SETTINGS=".claude/settings.local.json"

# Trailing path fragments that uniquely identify Syndicate's two entries.
F1="/.syndicate/hooks/session-start-syndicate.sh"
F2="/.syndicate/hooks/session-end-ledger.sh"

case "${1:-}" in
    -h|--help)
        echo "Usage: syndicate-deactivate"
        echo "  Removes Syndicate's SessionStart/SessionEnd entries from ${LOCAL_SETTINGS} (cwd)."
        exit 0 ;;
    "") ;;
    *)
        echo "Unknown argument: $1" >&2
        echo "Usage: syndicate-deactivate" >&2
        exit 1 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "⚠  jq not found — syndicate-deactivate needs jq to edit settings JSON safely."
    exit 1
fi

# Two-level removal (same logic as syndicate-activate --remove-global):
#   (a) drop an outer element whose inner .hooks[] are ALL ours
#   (b) for a multi-hook outer element, drop only the matching inner .hooks[]
#       and keep the matcher + sibling hooks.
remove_syn_entries() {
    local file="$1" tmp
    if [ ! -f "$file" ]; then
        echo "  ○ ${file} absent — nothing to deactivate"
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
            echo "  ✓ removed Syndicate entries from ${file} (siblings + other keys preserved)"
        fi
    else
        rm -f "$tmp"
        echo "  ⚠ jq transform failed — ${file} left UNCHANGED"
    fi
}

echo "━━━ Deactivating Syndicate self-dispatch for this repo ━━━"
remove_syn_entries "$LOCAL_SETTINGS"
echo "✓ Done."
