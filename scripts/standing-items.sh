#!/usr/bin/env bash
# standing-items.sh — Syndicate prospective-memory CLI ("Opt 1′")
#
# Prospective memory = "remember-to-do-X, surfaced when it is DUE." Today
# future-intent items (standing TODOs, deferred work) get dropped. This is the
# minimal store + surfacing mechanism: an append-only line store, a write-time
# "must be dated" gate, and a `due` query the SessionStart hook prints at boot.
#
# NO condition/prompt-matching triggers, NO daemon/scheduler — surfacing is a
# hook reading this file, nothing else.
#
# Store:  ~/.syndicate/prospective/standing-items.md   (override with
#         STANDING_ITEMS_STORE for tests).
# Repo scope for `due` is derived from `git remote get-url origin` / cwd, or
# overridden with STANDING_ITEMS_REPO (tests).
#
# Subcommands:
#   add --due <YYYY-MM-DD|next-session> [--repo <scope>] "<description>"
#   due            print only DUE open items (compact, hard-capped)
#   list           print all OPEN items
#   close <id>     mark an item done in-place (never deletes the line)

set -euo pipefail

STORE="${STANDING_ITEMS_STORE:-${HOME}/.syndicate/prospective/standing-items.md}"
DUE_CAP=5          # hard cap on lines printed by `due`
STALE_DAYS=14      # past-due beyond this many days → tag (never auto-delete)

write_header() {
    cat > "$1" << 'HDR'
# Syndicate — Standing Items  (prospective-memory store, "Opt 1′")
#
# Prospective memory = "remember-to-do-X, surfaced when it is DUE."
# One item per line, line-oriented:
#   - [ ] <id> | due:<YYYY-MM-DD|next-session> | repo:<scope|any> | added:<YYYY-MM-DD> | <description>
#
# DISCIPLINE — append-only / superseded-not-deleted:
#   * NEVER delete a line.
#   * Closing an item flips "- [ ]" -> "- [x]" and appends "| closed:<date>"
#     (mark-in-place; the line stays). Superseded/closed items remain visible.
#   * Every item MUST carry a due: value — an undated item is always-due, the
#     unbounded-growth / alert-fatigue vector. The CLI rejects undated adds.
#
# SURFACING — DUE items are printed by the SessionStart hook (see
#   hooks/session-start-syndicate.sh) via `standing-items.sh due`.
#
# KNOWN BOUNDARY (not a silent drop): that SessionStart hook fires ONLY in
#   Syndicate-ACTIVATED repos (layered mode). So a repo:any GLOBAL item will
#   NOT surface while you are in a non-activated repo; a repo:<scope> item
#   surfaces only when that repo is activated. Run `standing-items.sh due`
#   manually anywhere. This is an accepted limitation, stated plainly.
#
# Manage with: standing-items.sh  add|due|list|close
HDR
}

init_store() {
    if [ ! -f "$STORE" ]; then
        mkdir -p "$(dirname "$STORE")"
        write_header "$STORE"
    fi
}

# Current repo scope: explicit override, else origin remote basename, else cwd.
current_repo_scope() {
    if [ -n "${STANDING_ITEMS_REPO:-}" ]; then
        printf '%s' "$STANDING_ITEMS_REPO"
        return
    fi
    local url
    url=$(git remote get-url origin 2>/dev/null || true)
    if [ -n "$url" ]; then
        basename "$url" .git
    else
        basename "$(pwd)"
    fi
}

# Extract a "key:value" field value from a store line (fields are "| "-separated).
field_val() {
    local line="$1" key="$2"
    printf '%s\n' "$line" | grep -oE "${key}:[^|]*" | head -1 \
        | sed -E "s/^${key}: *//; s/ *$//" || true
}

usage() {
    cat >&2 << 'USAGE'
Usage:
  standing-items.sh add --due <YYYY-MM-DD|next-session> [--repo <scope>] "<description>"
  standing-items.sh due
  standing-items.sh list
  standing-items.sh close <id>
USAGE
}

ACTION="${1:-}"
shift || true

case "$ACTION" in
    add)
        due="" ; repo="any" ; desc=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --due)
                    [ $# -ge 2 ] || { echo "standing-items.sh add: --due needs a value" >&2; exit 1; }
                    due="$2"; shift 2 ;;
                --repo)
                    [ $# -ge 2 ] || { echo "standing-items.sh add: --repo needs a value" >&2; exit 1; }
                    repo="$2"; shift 2 ;;
                --) shift; desc="$*"; break ;;
                -*) echo "standing-items.sh add: unknown option: $1" >&2; exit 2 ;;
                *) desc="$*"; break ;;
            esac
        done

        # WRITE-TIME GATE (mandatory): undated items are always-due — refuse them.
        if [ -z "$due" ]; then
            echo "standing-items.sh add: --due is REQUIRED (YYYY-MM-DD or next-session)." >&2
            echo "  An undated item is always-due — the unbounded-growth / alert-fatigue vector. Refusing." >&2
            exit 1
        fi
        if [ -z "$desc" ]; then
            echo "standing-items.sh add: a <description> is required." >&2
            exit 1
        fi
        if [ "$due" != "next-session" ] && ! date -d "$due" +%s >/dev/null 2>&1; then
            echo "standing-items.sh add: --due must be a valid YYYY-MM-DD date or 'next-session' (got: '$due')." >&2
            exit 1
        fi

        init_store
        today=$(date +%F)
        id="si-$(printf '%s%s' "$(date +%s%N)" "${RANDOM}" | sha1sum | head -c 8)"
        # flock the store for the append (concurrent-agent race).
        (
            flock -x 9
            printf -- '- [ ] %s | due:%s | repo:%s | added:%s | %s\n' \
                "$id" "$due" "$repo" "$today" "$desc" >> "$STORE"
        ) 9>"$STORE.lock"
        echo "[standing-items] added ${id} (due:${due} repo:${repo})"
        ;;

    list)
        init_store
        grep -E '^- \[ \] ' "$STORE" 2>/dev/null || true
        ;;

    due)
        init_store
        scope=$(current_repo_scope)
        today_epoch=$(date -d "$(date +%F)" +%s)

        mapfile -t open_lines < <(grep -E '^- \[ \] ' "$STORE" 2>/dev/null || true)
        due_lines=()
        for line in "${open_lines[@]}"; do
            [ -n "$line" ] || continue
            dueval=$(field_val "$line" due)
            repoval=$(field_val "$line" repo)

            # repo filter: `any` always matches, else scope must equal current repo.
            if [ "$repoval" != "any" ] && [ "$repoval" != "$scope" ]; then
                continue
            fi

            time_due=0 ; stale=0
            if [ "$dueval" = "next-session" ]; then
                time_due=1
            else
                due_epoch=$(date -d "$dueval" +%s 2>/dev/null || true)
                if [ -n "$due_epoch" ] && [ "$due_epoch" -le "$today_epoch" ]; then
                    time_due=1
                    if [ $(( (today_epoch - due_epoch) / 86400 )) -gt "$STALE_DAYS" ]; then
                        stale=1
                    fi
                fi
            fi
            [ "$time_due" -eq 1 ] || continue

            if [ "$stale" -eq 1 ]; then
                due_lines+=("${line}  (stale — done or re-defer?)")
            else
                due_lines+=("$line")
            fi
        done

        total=${#due_lines[@]}
        [ "$total" -eq 0 ] && exit 0

        if [ "$total" -le "$DUE_CAP" ]; then
            printf '%s\n' "${due_lines[@]}"
        else
            # Overflow: never dump the whole store. Show the first few, then
            # collapse the rest into ONE escalating line (escalate, not hide).
            for (( i=0; i<DUE_CAP-1; i++ )); do
                printf '%s\n' "${due_lines[$i]}"
            done
            printf '⚠ %s standing items due — run: standing-items.sh list\n' "$total"
        fi
        ;;

    close)
        id="${1:-}"
        [ -n "$id" ] || { echo "standing-items.sh close: <id> required" >&2; exit 1; }
        init_store
        today=$(date +%F)
        if ! grep -qE "^- \[ \] ${id} " "$STORE"; then
            echo "standing-items.sh close: no OPEN item with id '${id}'" >&2
            exit 1
        fi
        # Mark in place: append "| closed:<date>" then flip the checkbox. Never delete.
        (
            flock -x 9
            sed -i "/^- \[ \] ${id} /{s/\$/ | closed:${today}/; s/^- \[ \] /- [x] /;}" "$STORE"
        ) 9>"$STORE.lock"
        echo "[standing-items] closed ${id}"
        ;;

    ""|-h|--help|help)
        usage
        [ -z "$ACTION" ] && exit 1 || exit 0
        ;;

    *)
        echo "standing-items.sh: unknown subcommand: ${ACTION}" >&2
        usage
        exit 1
        ;;
esac
