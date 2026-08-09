#!/usr/bin/env bash
# loki-log.sh — append a structured finding to Loki's improvement log
#
# Writes to a STABLE path (~/.syndicate/loki/YYYY-MM.md) so it works from ANY
# project, not just inside the Syndicate repo. /retro calls this automatically
# for every finding it produces; /loki-review reads and syncs these later.
#
# Each finding is one record with a status tag so the month-end review can tell
# what was already fixed from what's still open.
#
# Usage:
#   loki-log.sh --status applied \
#     --finding "Scribe recraft skipped on multi-part request" \
#     --doctrine "Step 0.5 says recraft substantial requests" \
#     --severity low \
#     --action "Added enumerated-request skip clause to doctrine" \
#     --session "Mantelpiece reachability reconstruction"
#
# Status values:
#   applied  — fixed during the retro/session (most common)
#   open     — real finding, not yet fixed (needs future work)
#   carried  — known issue we don't own / won't fix here (e.g. BJ's hook)
#   wontfix  — considered and deliberately declined
#
# READ-ONLY on everything except its own log file.

set -u

LOKI_DIR="${HOME}/.syndicate/loki"
mkdir -p "$LOKI_DIR"

# Month is passed in (the model knows the date; scripts can't call date reliably
# in all sandboxes). Falls back to `date` if available, else "undated".
MONTH=""
STATUS="open"
FINDING=""
DOCTRINE=""
SEVERITY="unknown"
ACTION=""
SESSION=""
TS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --month)    MONTH="$2"; shift 2 ;;
        --status)   STATUS="$2"; shift 2 ;;
        --finding)  FINDING="$2"; shift 2 ;;
        --doctrine) DOCTRINE="$2"; shift 2 ;;
        --severity) SEVERITY="$2"; shift 2 ;;
        --action)   ACTION="$2"; shift 2 ;;
        --session)  SESSION="$2"; shift 2 ;;
        --ts)       TS="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ -z "$FINDING" ]; then
    echo "loki-log: --finding is required" >&2
    exit 1
fi

# Resolve month/timestamp with a date fallback
[ -z "$MONTH" ] && MONTH="$(date +%Y-%m 2>/dev/null || echo undated)"
[ -z "$TS" ] && TS="$(date -Iseconds 2>/dev/null || echo unknown)"

LOG="${LOKI_DIR}/${MONTH}.md"

# Seed the month file with a header the first time
if [ ! -f "$LOG" ]; then
    {
        echo "# Loki Improvement Log — ${MONTH}"
        echo ""
        echo "> Auto-appended by /retro. Reviewed monthly by /loki-review."
        echo "> Status: applied | open | carried | wontfix"
        echo ""
    } > "$LOG"
fi

# Append the finding as a structured record
{
    echo "## [${STATUS}] ${FINDING}"
    echo "- **When:** ${TS}"
    [ -n "$SESSION" ]  && echo "- **Session:** ${SESSION}"
    echo "- **Severity:** ${SEVERITY}"
    [ -n "$DOCTRINE" ] && echo "- **Doctrine:** ${DOCTRINE}"
    [ -n "$ACTION" ]   && echo "- **Action taken:** ${ACTION}"
    echo ""
} >> "$LOG"

echo "logged [${STATUS}] → ${LOG}"
