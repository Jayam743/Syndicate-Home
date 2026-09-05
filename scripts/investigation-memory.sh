#!/usr/bin/env bash
# investigation-memory.sh — Specter's institutional memory for root causes
#
# Two modes:
#   query  — "have we diagnosed something like this before?" (run BEFORE investigating)
#   record — persist a resolved root cause (run AFTER a fix is confirmed)
#
# This is what BJ's per-incident /wtf can't do: it FORGETS between incidents.
# Specter remembers — a new "why is X broken" first checks whether we've already
# solved this exact symptom, and cites the prior fix.
#
# Store: ~/.syndicate/investigations/  (one .md per resolved investigation)
# READ-ONLY except its own store.
#
# Usage:
#   investigation-memory.sh query "headscale coppermind path 502"
#   investigation-memory.sh record --slug headscale-coppermind \
#     --symptom "502 on the API path" \
#     --root-cause "API_PATH unset in the service env" \
#     --fix "added env var to services/api/compose.yml" \
#     --repo example-repo --ts 2026-08-09T12:00:00

set -u

INV_DIR="${HOME}/.syndicate/investigations"
mkdir -p "$INV_DIR"

MODE="${1:-query}"
shift || true

case "$MODE" in
  query)
    QUERY="$*"
    if [ -z "$QUERY" ]; then echo "usage: investigation-memory.sh query \"symptom words\"" >&2; exit 1; fi

    # Keyword match against past investigations (symptom + root-cause lines),
    # ranked by number of matching terms then recency.
    STOP="the a an is are was why how what when where this that with can could i we it to of in on for and or but"
    mapfile -t KW < <(echo "$QUERY" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9_./-' ' ' | tr ' ' '\n' \
        | awk 'length>=3' | grep -vxF -f <(echo "$STOP" | tr ' ' '\n' | awk 'NF') 2>/dev/null)
    if [ "${#KW[@]}" -eq 0 ]; then echo "  (no usable keywords)"; exit 0; fi
    PAT="$(printf '%s|' "${KW[@]}")"; PAT="${PAT%|}"

    echo "── Prior investigations matching: ${KW[*]} ──"
    SCORED="$(mktemp)"
    for f in "$INV_DIR"/*.md; do
        [ -e "$f" ] || continue
        score="$(grep -icE "$PAT" "$f" 2>/dev/null | head -1)"; score="${score:-0}"
        [ "$score" -gt 0 ] 2>/dev/null || continue
        mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
        printf '%s\t%s\t%s\n' "$mtime" "$score" "$f" >> "$SCORED"
    done
    if [ -s "$SCORED" ]; then
        sort -t"$(printf '\t')" -k2,2nr -k1,1nr "$SCORED" | head -3 | while IFS=$'\t' read -r _ score path; do
            echo ""
            echo "  ▸ $(grep -m1 '^# ' "$path" 2>/dev/null | sed 's/^# //') (${score} matches)"
            grep -m1 '^- \*\*Root cause:\*\*' "$path" 2>/dev/null | sed 's/^- /    /'
            grep -m1 '^- \*\*Fix:\*\*' "$path" 2>/dev/null | sed 's/^- /    /'
            echo "    file: ${path}"
        done
        echo ""
        echo "  → If a match fits, START from its fix — don't re-investigate from zero."
    else
        echo "  (no prior investigation matches — this looks new; investigate fresh)"
    fi
    rm -f "$SCORED"
    ;;

  record)
    SLUG="" SYMPTOM="" ROOT="" FIX="" REPO="" TS="" VERIFIED=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --slug) SLUG="$2"; shift 2 ;;
        --symptom) SYMPTOM="$2"; shift 2 ;;
        --root-cause) ROOT="$2"; shift 2 ;;
        --fix) FIX="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        --ts) TS="$2"; shift 2 ;;
        --verified) VERIFIED="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -z "$SLUG" ] && SLUG="investigation"
    [ -z "$TS" ] && TS="$(date -Iseconds 2>/dev/null || echo unknown)"
    DATE="$(echo "$TS" | cut -dT -f1)"
    F="${INV_DIR}/${DATE}-${SLUG}.md"
    {
      echo "# ${SLUG}: ${SYMPTOM:-（no symptom）}"
      echo "- **When:** ${TS}"
      [ -n "$REPO" ] && echo "- **Repo:** ${REPO}"
      echo "- **Symptom:** ${SYMPTOM}"
      echo "- **Root cause:** ${ROOT}"
      echo "- **Fix:** ${FIX}"
      [ -n "$VERIFIED" ] && echo "- **Verified:** ${VERIFIED}"
    } > "$F"
    echo "recorded → ${F}"
    ;;

  *)
    echo "usage: investigation-memory.sh {query|record} ..." >&2
    exit 1 ;;
esac
