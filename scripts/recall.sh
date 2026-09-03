#!/usr/bin/env bash
# recall.sh — Context recall for Syndicate
#
# Given a query (e.g. "why is the login crashing"), this finds the most RELEVANT
# recent past sessions AND the repo's recent merge history, then emits a compact
# "context brief" that agents fold into their prompt — so troubleshooting starts
# with what you already know, not from zero.
#
# Design (per user intent):
#   - Keyword match against existing transcripts (NOTHING is moved)
#   - Ranked by SQLite FTS5/BM25 relevance, recency as tiebreak, capped at 2-3
#     sessions (don't go back too far). If python3/FTS5 or the index is
#     unavailable, falls back to a live grep keyword scan (marked, never silent).
#   - Plus recent merge history from GitLab/GitHub
#
# READ-ONLY. Touches nothing but stdout. Safe to run anytime.
#
# Usage:
#   ./scripts/recall.sh "why is the nightly job crashing"
#   ./scripts/recall.sh --max 3 --repo /path/to/repo "auth timeout error"

# Best-effort read tool: keep -u (catch unset-var bugs) but NOT -e/pipefail —
# a grep with no match must not abort the whole brief.
set -u

PROJECTS_DIR="${SYNDICATE_PROJECTS_DIR:-${HOME}/.claude/projects}"
MAX_SESSIONS=3
MAX_MRS=10
REPO_DIR="$(pwd)"
QUERY=""

# BM25 index (SQLite FTS5) — the primary Part-1 scorer, with the legacy grep scan
# as fallback. The .db lives under ~/.syndicate (ext4 $HOME), NEVER in the repo tree
# on the WSL /mnt/c mount (SQLite locking hazard). Overridable for tests.
RECALL_DB="${SYNDICATE_RECALL_DB:-${HOME}/.syndicate/kb/recall-index.db}"
# Resolve THIS script's real dir (may be invoked via a ~/.syndicate/scripts symlink)
# so we find the repo-local helper even when scripts/lib isn't symlinked out.
RECALL_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
RECALL_LIB_DIR="$(cd "$(dirname "$RECALL_SELF")/lib" 2>/dev/null && pwd || echo "")"
INDEX_PY="${RECALL_LIB_DIR}/recall-index.py"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max) MAX_SESSIONS="$2"; shift 2 ;;
        --repo) REPO_DIR="$2"; shift 2 ;;
        --mrs) MAX_MRS="$2"; shift 2 ;;
        *) QUERY="${QUERY} $1"; shift ;;
    esac
done
QUERY="$(echo "$QUERY" | sed 's/^ *//;s/ *$//')"

if [ -z "$QUERY" ]; then
    echo "usage: recall.sh [--max N] [--repo DIR] \"your question or error\"" >&2
    exit 1
fi

# --- Extract keywords from the query ---
# Drop common stopwords; keep meaningful terms (3+ chars). Also keep any
# error-ish tokens (CamelCase, snake_case, ALL_CAPS, things with dots/slashes).
STOPWORDS="the a an is are was were why how what when where this that these those
we i you it to of in on for and or but with can could would should fix make better
does do doesn error crashing crash broken help please"

keywords() {
    echo "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9_./-' ' ' | tr ' ' '\n' \
        | awk 'length($0) >= 3' \
        | grep -vxF -f <(echo "$STOPWORDS" | tr ' ' '\n' | awk 'NF') 2>/dev/null || true
}

mapfile -t KW < <(keywords "$QUERY")
if [ "${#KW[@]}" -eq 0 ]; then
    # Fall back to raw significant words if everything got filtered
    mapfile -t KW < <(echo "$QUERY" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9_' ' ' | tr ' ' '\n' | awk 'length>=4')
fi
# Build a grep alternation pattern
PATTERN="$(printf '%s|' "${KW[@]}")"
PATTERN="${PATTERN%|}"

echo "═══════════════════════════════════════════════════"
echo "SYNDICATE CONTEXT BRIEF"
echo "Query: ${QUERY}"
echo "Keywords: ${KW[*]:-<none>}"
echo "═══════════════════════════════════════════════════"

# --- Part 1: Relevant past sessions (across ALL projects, recency-ranked) ---
echo ""
echo "── Relevant past sessions (top ${MAX_SESSIONS}) ──"

if [ ! -d "$PROJECTS_DIR" ] || [ -z "$PATTERN" ]; then
    echo "  (no transcript history available)"
else
    # Scored rows are "mtime<TAB>score<TAB>path", higher score == more relevant.
    # Downstream sort (-k2,2nr -k1,1nr) ranks by score then recency for BOTH
    # scorers, so the recency tiebreak is preserved regardless of which ran.
    SCORED="$(mktemp)"

    # --- Primary scorer: SQLite FTS5/BM25 over the SAME transcript corpus. ---
    # Available iff python3 + FTS5 are present AND the query ran against a
    # populated index (exit 0). Exit 3 (index missing/empty) or any error → fall
    # back to the live grep scan, so an index-miss is never a silent no-search.
    SCORER="grep"
    if command -v python3 >/dev/null 2>&1 && [ -f "$INDEX_PY" ] \
       && python3 "$INDEX_PY" probe >/dev/null 2>&1; then
        if python3 "$INDEX_PY" query --db "$RECALL_DB" "${KW[@]}" > "$SCORED" 2>/dev/null; then
            SCORER="bm25"
        else
            : > "$SCORED"   # index unavailable/unusable — reset for grep fallback
        fi
    fi

    # --- Fallback scorer: live grep scan (also the honest "we DID search" path
    #     when the BM25 index is absent, empty, cold-building, or unusable). ---
    if [ "$SCORER" != "bm25" ]; then
        echo "  (note: BM25 index unavailable — used live keyword scan)"
        while IFS= read -r -d '' f; do
            # Count lines matching any keyword (case-insensitive).
            # grep -c prints 0 and exits 1 on no-match, so take first line only.
            score="$(grep -icE "$PATTERN" "$f" 2>/dev/null | head -1)"
            score="${score:-0}"
            [ "$score" -gt 0 ] 2>/dev/null || continue
            mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
            printf '%s\t%s\t%s\n' "$mtime" "$score" "$f" >> "$SCORED"
        done < <(find "$PROJECTS_DIR" -name "*.jsonl" -print0 2>/dev/null)
    fi

    if [ ! -s "$SCORED" ]; then
        echo "  (no past sessions mention: ${KW[*]})"
    else
        # Rank: primarily by score, tie-break by recency (both descending)
        sort -t"$(printf '\t')" -k2,2nr -k1,1nr "$SCORED" | head -n "$MAX_SESSIONS" | \
        while IFS=$'\t' read -r mtime score path; do
            # Session title (aiTitle) and date
            title="$(grep -m1 '"ai-title"' "$path" 2>/dev/null | jq -r '.aiTitle // empty' 2>/dev/null || true)"
            [ -z "$title" ] && title="(untitled session)"
            date="$(date -d "@$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
            proj="$(basename "$(dirname "$path")")"

            echo ""
            echo "  ▸ ${title}"
            if [ "$SCORER" = "bm25" ]; then
                echo "    ${date} · ${proj} · BM25 relevance ${score}"
            else
                echo "    ${date} · ${proj} · ${score} matching lines"
            fi

            # Pull up to 2 representative matching USER messages (what you asked)
            grep -iE "$PATTERN" "$path" 2>/dev/null \
                | jq -r 'select(.type=="user") | (.message.content | if type=="string" then . else (.[0].text // "") end)' 2>/dev/null \
                | grep -iE "$PATTERN" 2>/dev/null | head -2 | while IFS= read -r line; do
                    snippet="$(echo "$line" | tr '\n' ' ' | cut -c1-120)"
                    [ -n "$snippet" ] && echo "      \"${snippet}...\""
                done || true
        done
    fi
    rm -f "$SCORED"
fi

# --- Part 2: Recent merge history from the repo ---
echo ""
echo "── Recent merge history (${REPO_DIR##*/}) ──"

if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    REMOTE="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo '')"
    MR_OUT=""
    if echo "$REMOTE" | grep -qi gitlab && command -v glab >/dev/null 2>&1; then
        MR_OUT="$(glab mr list --merged --per-page "$MAX_MRS" -R "$REPO_DIR" 2>/dev/null | head -n "$MAX_MRS")"
    elif echo "$REMOTE" | grep -qi github && command -v gh >/dev/null 2>&1; then
        MR_OUT="$(gh pr list --state merged --limit "$MAX_MRS" 2>/dev/null)"
    fi

    # If the CLI gave us something useful, show it. Otherwise ALWAYS fall back to
    # local git merge history (works offline / when glab-gh isn't authed).
    if [ -n "$(echo "$MR_OUT" | tr -d '[:space:]')" ]; then
        echo "$MR_OUT" | sed 's/^/  /'
    else
        # Fetch first so the local merge log isn't stale (best-effort, non-blocking;
        # a stale ref falsely shows merges as absent — see doctrine "fetch before
        # you reconstruct"). Quiet + short timeout so offline/slow remotes don't hang.
        if command -v timeout >/dev/null 2>&1; then
            timeout 15 git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null || true
        else
            git -C "$REPO_DIR" fetch --quiet origin 2>/dev/null || true
        fi
        echo "  (remote MR/PR list unavailable — using local git merge log, post-fetch)"
        LOCAL_MERGES="$(git -C "$REPO_DIR" log --merges --oneline -n "$MAX_MRS" 2>/dev/null)"
        if [ -n "$LOCAL_MERGES" ]; then
            echo "$LOCAL_MERGES" | sed 's/^/  /'
        else
            echo "  (no merge commits found)"
        fi
    fi
else
    echo "  (not a git repo: ${REPO_DIR})"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "Use this brief as PRIOR CONTEXT. Don't re-ask what's"
echo "already answered above. Build on it."
echo "═══════════════════════════════════════════════════"
