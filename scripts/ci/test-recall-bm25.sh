#!/usr/bin/env bash
# Regression test for scripts/recall.sh's FTS5/BM25 scorer + its grep fallback.
#
# Hermetic: temp corpus via SYNDICATE_PROJECTS_DIR and a temp index via
# SYNDICATE_RECALL_DB — never touches the real ~/.claude/projects or ~/.syndicate.
# FTS5-dependent cases skip cleanly (not fail) when python3/FTS5 is unavailable, so
# the suite is never flaky on a box without them; the grep-fallback + honest-empty +
# Part-2-unchanged cases always run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECALL="${SCRIPT_DIR}/../recall.sh"
INDEX_PY="${SCRIPT_DIR}/../lib/recall-index.py"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0; FAIL=0; SKIP=0; FAILURES=()
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
skip() { echo "  SKIP: $1 — $2"; SKIP=$((SKIP+1)); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

echo "--- recall.sh BM25 scorer + fallback ---"

# Is FTS5 available? Gate the index-dependent cases on this.
HAVE_FTS=0
if command -v python3 >/dev/null 2>&1 && [ -f "$INDEX_PY" ] \
   && python3 "$INDEX_PY" probe >/dev/null 2>&1; then
    HAVE_FTS=1
fi

# ---------------------------------------------------------------------------
# (a) Index missing/unusable → falls back to grep (NOT a silent empty).
#     Corpus has a matching session; no db exists. Expect: the marked fallback
#     note AND the matching session surfaced AND exit 0.
# ---------------------------------------------------------------------------
PROJ="${TMPROOT}/a/projects/projX"; mkdir -p "$PROJ"
printf '{"type":"user","message":{"content":"the widgetflux crashed hard"}}\n' > "${PROJ}/s.jsonl"
OUT="$(SYNDICATE_PROJECTS_DIR="${TMPROOT}/a/projects" SYNDICATE_RECALL_DB="${TMPROOT}/a/nope.db" \
       bash "$RECALL" --repo "${TMPROOT}/a" "widgetflux" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] \
   && printf '%s' "$OUT" | grep -qF "BM25 index unavailable" \
   && printf '%s' "$OUT" | grep -qF "projX" \
   && ! printf '%s' "$OUT" | grep -qF "no past sessions mention"; then
    ok "a_index_missing_falls_back_to_grep"
else fail "a_index_missing_falls_back_to_grep" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (b) Empty corpus → exit 0 + honest empty state (searched, found nothing).
# ---------------------------------------------------------------------------
mkdir -p "${TMPROOT}/b/projects"
OUT="$(SYNDICATE_PROJECTS_DIR="${TMPROOT}/b/projects" SYNDICATE_RECALL_DB="${TMPROOT}/b/nope.db" \
       bash "$RECALL" --repo "${TMPROOT}/b" "anythingatall" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "no past sessions mention"; then
    ok "b_empty_corpus_exit0_honest_empty"
else fail "b_empty_corpus_exit0_honest_empty" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (c) Recency tiebreak preserved (grep path, no FTS needed): two docs with the
#     SAME match count → the newer one is ranked first.
# ---------------------------------------------------------------------------
OLD="${TMPROOT}/c/projects/aaa-old"; NEW="${TMPROOT}/c/projects/zzz-new"; mkdir -p "$OLD" "$NEW"
printf '{"type":"user","message":{"content":"tiebreaktoken older one"}}\n' > "${OLD}/s.jsonl"
printf '{"type":"user","message":{"content":"tiebreaktoken newer one"}}\n' > "${NEW}/s.jsonl"
touch -d '2026-01-01' "${OLD}/s.jsonl"
touch -d '2026-08-01' "${NEW}/s.jsonl"
OUT="$(SYNDICATE_PROJECTS_DIR="${TMPROOT}/c/projects" SYNDICATE_RECALL_DB="${TMPROOT}/c/nope.db" \
       bash "$RECALL" --repo "${TMPROOT}/c" "tiebreaktoken" 2>&1)"; RC=$?
NEW_LINE="$(printf '%s' "$OUT" | grep -n 'zzz-new' | head -1 | cut -d: -f1)"
OLD_LINE="$(printf '%s' "$OUT" | grep -n 'aaa-old' | head -1 | cut -d: -f1)"
if [ "$RC" -eq 0 ] && [ -n "$NEW_LINE" ] && [ -n "$OLD_LINE" ] && [ "$NEW_LINE" -lt "$OLD_LINE" ]; then
    ok "c_recency_tiebreak_newer_first"
else fail "c_recency_tiebreak_newer_first" "rc=$RC new@$NEW_LINE old@$OLD_LINE out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (d) Part-2 (merge history) block byte-unchanged vs git HEAD — the scorer swap
#     must not touch Part 2. Static code diff; skips cleanly outside a git repo.
# ---------------------------------------------------------------------------
MARKER='# --- Part 2: Recent merge history from the repo ---'
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$REPO_ROOT" show "HEAD:scripts/recall.sh" >/dev/null 2>&1; then
    NOW_P2="$(awk -v m="$MARKER" 'index($0,m){f=1} f' "$RECALL")"
    HEAD_P2="$(git -C "$REPO_ROOT" show HEAD:scripts/recall.sh | awk -v m="$MARKER" 'index($0,m){f=1} f')"
    if [ -n "$NOW_P2" ] && [ "$NOW_P2" = "$HEAD_P2" ]; then
        ok "d_part2_merge_block_unchanged"
    else fail "d_part2_merge_block_unchanged" "Part-2 block differs from HEAD (or marker missing)"; fi
else
    skip "d_part2_merge_block_unchanged" "not a git repo / no HEAD copy of recall.sh"
fi

# ===========================================================================
# FTS5-dependent cases below.
# ===========================================================================
if [ "$HAVE_FTS" -ne 1 ]; then
    skip "e_fts5_term_escaping" "python3/FTS5 unavailable"
    skip "f_bm25_rare_outranks_common" "python3/FTS5 unavailable"
    skip "g_incremental_indexes_new_file" "python3/FTS5 unavailable"
    skip "h_prefix_recall_not_narrowed_below_grep" "python3/FTS5 unavailable"
else
    # Build a small index once for the escaping + ranking cases.
    EPROJ="${TMPROOT}/e/projects/projE"; mkdir -p "$EPROJ"
    printf '{"type":"user","content":"auth-timeout in src/x and foo.bar"}\n' > "${EPROJ}/s.jsonl"
    EDB="${TMPROOT}/e/kb/recall-index.db"; mkdir -p "${TMPROOT}/e/kb"
    python3 "$INDEX_PY" index --db "$EDB" --projects "${TMPROOT}/e/projects" >/dev/null 2>&1

    # (e) Escaping: hyphen, path, and a bare double-quote must NOT throw. A crash
    #     is exit 2 / non-empty stderr; acceptable is rc 0 (matched) or 3 (no rows).
    ERR="$(python3 "$INDEX_PY" query --db "$EDB" 'auth-timeout' 'src/x' 'foo.bar' '"' '*' 'AND' 2>&1 >/dev/null)"; RC=$?
    if { [ "$RC" -eq 0 ] || [ "$RC" -eq 3 ]; } && [ -z "$ERR" ]; then
        # Also prove end-to-end recall.sh survives a nasty query string with exit 0.
        OUT="$(SYNDICATE_PROJECTS_DIR="${TMPROOT}/e/projects" SYNDICATE_RECALL_DB="$EDB" \
               bash "$RECALL" --repo "${TMPROOT}/e" 'auth-timeout src/x foo.bar "*"' 2>&1)"; RC2=$?
        if [ "$RC2" -eq 0 ]; then
            ok "e_fts5_term_escaping"
        else fail "e_fts5_term_escaping" "recall.sh rc=$RC2 out='$OUT'"; fi
    else fail "e_fts5_term_escaping" "query rc=$RC err='$ERR'"; fi

    # (f) BM25 ranking: a SHORT doc matching a RARE term outranks a LONG doc (and
    #     many fillers) matching only a COMMON term — the whole point vs raw-count.
    RPROJ="${TMPROOT}/f/projects/projR"; mkdir -p "$RPROJ"
    printf '{"type":"user","content":"zephyrquux occurred once"}\n' > "${RPROJ}/rare.jsonl"
    for i in 1 2 3 4 5; do
        printf '{"type":"user","content":"commonword note %s"}\n' "$i" > "${RPROJ}/f${i}.jsonl"
    done
    python3 - "${RPROJ}/big.jsonl" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as fh:
    for i in range(800):
        fh.write('{"type":"user","content":"commonword commonword commonword filler %d"}\n' % i)
PYEOF
    RDB="${TMPROOT}/f/kb/recall-index.db"; mkdir -p "${TMPROOT}/f/kb"
    python3 "$INDEX_PY" index --db "$RDB" --projects "${TMPROOT}/f/projects" >/dev/null 2>&1
    TOP="$(python3 "$INDEX_PY" query --db "$RDB" zephyrquux commonword 2>/dev/null | head -1 | cut -f3)"
    if [ "$TOP" = "${RPROJ}/rare.jsonl" ]; then
        ok "f_bm25_rare_outranks_common"
    else fail "f_bm25_rare_outranks_common" "top='$TOP' (expected rare.jsonl)"; fi

    # (g) Incremental: a file added after the cold build becomes queryable, and no
    #     stray WAL/SHM sidecars are left beside the live db.
    sleep 1
    printf '{"type":"user","content":"brandnewtoken appeared later"}\n' > "${RPROJ}/new.jsonl"
    python3 "$INDEX_PY" index --db "$RDB" --projects "${TMPROOT}/f/projects" >/dev/null 2>&1
    GOT="$(python3 "$INDEX_PY" query --db "$RDB" brandnewtoken 2>/dev/null | head -1 | cut -f3)"
    if [ "$GOT" = "${RPROJ}/new.jsonl" ]; then
        ok "g_incremental_indexes_new_file"
    else fail "g_incremental_indexes_new_file" "got='$GOT' (expected new.jsonl)"; fi

    # (h) Prefix recall: a query term that is a PREFIX/substring of a corpus token
    #     (auth→authentication, timeout→timeouts) must still surface under BM25.
    #     Exact-token matching (the pre-fix bug) returned 0 rows here, silently
    #     narrowing recall below the grep path and emitting a false "found nothing".
    HPROJ="${TMPROOT}/h/projects/projH"; mkdir -p "$HPROJ"
    printf '{"type":"user","content":"we hit authentication timeouts in prod"}\n' > "${HPROJ}/s.jsonl"
    HDB="${TMPROOT}/h/kb/recall-index.db"; mkdir -p "${TMPROOT}/h/kb"
    python3 "$INDEX_PY" index --db "$HDB" --projects "${TMPROOT}/h/projects" >/dev/null 2>&1
    HGOT="$(python3 "$INDEX_PY" query --db "$HDB" auth timeout 2>/dev/null | head -1 | cut -f3)"; HRC=$?
    if [ "$HGOT" = "${HPROJ}/s.jsonl" ]; then
        ok "h_prefix_recall_not_narrowed_below_grep"
    else fail "h_prefix_recall_not_narrowed_below_grep" "got='$HGOT' rc=$HRC (expected s.jsonl)"; fi
fi

echo ""
TOTAL=$((PASS+FAIL+SKIP))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS — ${TOTAL} cases (${PASS} passed, ${SKIP} skipped, 0 failed)"; exit 0
else
    echo "FAIL — ${TOTAL} cases (${PASS} passed, ${SKIP} skipped, ${FAIL} failed)"
    printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
