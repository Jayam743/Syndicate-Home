#!/usr/bin/env bash
# Regression test for scripts/transcript-ingest.sh.
# Hermetic: a temp dest dir (via SYNDICATE_TRANSCRIPT_DIR), a temp HOME for the
# transcript-dir file, and a MOCK `markitdown` shim on PATH whose behavior (success /
# empty-output / failure) is driven by env vars. Never touches the real transcript dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGEST="${SCRIPT_DIR}/../transcript-ingest.sh"
PASS=0; FAIL=0; FAILURES=()
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

MOCKBIN="${TMPROOT}/mockbin"
mkdir -p "$MOCKBIN"

# Mock markitdown honoring `<input> -o <out>`. Behavior driven by MOCK_MODE:
#   success (default) → writes $MOCK_CONTENT to the -o target
#   empty             → creates a 0-byte -o target, exit 0
#   fail              → exits 3 without writing
cat > "${MOCKBIN}/markitdown" << 'EOF'
#!/usr/bin/env bash
out=""
prev=""
for a in "$@"; do
    if [ "$prev" = "-o" ]; then out="$a"; fi
    prev="$a"
done
mode="${MOCK_MODE:-success}"
case "$mode" in
    fail)  exit 3 ;;
    empty) : > "$out"; exit 0 ;;
    *)     printf '%s\n' "${MOCK_CONTENT:-# converted transcript}" > "$out"; exit 0 ;;
esac
EOF
chmod +x "${MOCKBIN}/markitdown"

echo "--- transcript-ingest.sh ---"

# Fixtures.
SRC="${TMPROOT}/call-42.docx"
printf 'binary-ish source' > "$SRC"
INPUT="$SRC"

# ---------------------------------------------------------------------------
# (a) Resolution order: env > file > fallback.
# ---------------------------------------------------------------------------
FAKE_HOME="${TMPROOT}/home"; mkdir -p "${FAKE_HOME}/.syndicate"
printf '%s\n' "${TMPROOT}/from-file" > "${FAKE_HOME}/.syndicate/transcript-dir"

# env wins over the file.
ENV_DEST="${TMPROOT}/from-env"
OUT="$(PATH="${MOCKBIN}:${PATH}" HOME="$FAKE_HOME" SYNDICATE_TRANSCRIPT_DIR="$ENV_DEST" MOCK_MODE=success bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "dest → ${ENV_DEST}" && [ -f "${ENV_DEST}/call-42.md" ]; then
    ok "a1_env_over_file"
else fail "a1_env_over_file" "rc=$RC out='$OUT'"; fi

# file wins over fallback when env unset.
OUT="$(PATH="${MOCKBIN}:${PATH}" HOME="$FAKE_HOME" MOCK_MODE=success bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "dest → ${TMPROOT}/from-file" && [ -f "${TMPROOT}/from-file/call-42.md" ]; then
    ok "a2_file_over_fallback"
else fail "a2_file_over_fallback" "rc=$RC out='$OUT'"; fi

# fallback when neither env nor file present.
FALLBACK_HOME="${TMPROOT}/home2"; mkdir -p "$FALLBACK_HOME"
OUT="$(PATH="${MOCKBIN}:${PATH}" HOME="$FALLBACK_HOME" MOCK_MODE=success bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "dest → ${FALLBACK_HOME}/.syndicate/transcripts" && [ -f "${FALLBACK_HOME}/.syndicate/transcripts/call-42.md" ]; then
    ok "a3_fallback"
else fail "a3_fallback" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (b) dest is echoed on every run.
# ---------------------------------------------------------------------------
D="${TMPROOT}/echo-dest"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=success bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if printf '%s' "$OUT" | grep -qF "[transcript-ingest] dest → ${D}"; then
    ok "b_dest_echoed"
else fail "b_dest_echoed" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (c) missing input → BLOCK (nonzero).
# ---------------------------------------------------------------------------
D="${TMPROOT}/missing"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" bash "$INGEST" "${TMPROOT}/nope.docx" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'BLOCK'; then
    ok "c_missing_input_blocks"
else fail "c_missing_input_blocks" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (d) markitdown failure → BLOCK + no 0-byte file left.
# ---------------------------------------------------------------------------
D="${TMPROOT}/failmode"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=fail bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'BLOCK' && [ ! -e "${D}/call-42.md" ]; then
    ok "d_markitdown_fail_blocks_no_file"
else fail "d_markitdown_fail_blocks_no_file" "rc=$RC out='$OUT' present=$([ -e "${D}/call-42.md" ] && echo yes || echo no)"; fi

# ---------------------------------------------------------------------------
# (e) empty output → BLOCK + no 0-byte file left.
# ---------------------------------------------------------------------------
D="${TMPROOT}/emptymode"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=empty bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'BLOCK' && [ ! -e "${D}/call-42.md" ]; then
    ok "e_empty_output_blocks_no_file"
else fail "e_empty_output_blocks_no_file" "rc=$RC out='$OUT' present=$([ -e "${D}/call-42.md" ] && echo yes || echo no)"; fi

# ---------------------------------------------------------------------------
# (f) successful convert → <name>.md in dest, disposition=converted.
# ---------------------------------------------------------------------------
D="${TMPROOT}/happy"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=success MOCK_CONTENT="# hello" bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -f "${D}/call-42.md" ] && printf '%s' "$OUT" | grep -q 'disposition: converted'; then
    ok "f_convert_writes_named_md"
else fail "f_convert_writes_named_md" "rc=$RC out='$OUT'"; fi

# ---------------------------------------------------------------------------
# (g) collision identical → SKIP (idempotent), no new file.
# ---------------------------------------------------------------------------
before_count="$(find "$D" -maxdepth 1 -name '*.md' | wc -l)"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=success MOCK_CONTENT="# hello" bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
after_count="$(find "$D" -maxdepth 1 -name '*.md' | wc -l)"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'disposition: skipped-identical' && [ "$before_count" -eq "$after_count" ]; then
    ok "g_collision_identical_skips"
else fail "g_collision_identical_skips" "rc=$RC out='$OUT' before=$before_count after=$after_count"; fi

# ---------------------------------------------------------------------------
# (h) collision different → timestamped file + original untouched.
# ---------------------------------------------------------------------------
orig_content="$(cat "${D}/call-42.md")"
OUT="$(PATH="${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D" MOCK_MODE=success MOCK_CONTENT="# DIFFERENT now" bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
stamped_count="$(find "$D" -maxdepth 1 -name 'call-42-*.md' | wc -l)"
now_content="$(cat "${D}/call-42.md")"
if [ "$RC" -eq 0 ] \
   && printf '%s' "$OUT" | grep -q 'disposition: collision-timestamped' \
   && [ "$stamped_count" -ge 1 ] \
   && [ "$orig_content" = "$now_content" ]; then
    ok "h_collision_diff_timestamps_and_preserves"
else fail "h_collision_diff_timestamps_and_preserves" "rc=$RC out='$OUT' stamped=$stamped_count preserved=$([ "$orig_content" = "$now_content" ] && echo yes || echo no)"; fi

# ---------------------------------------------------------------------------
# (i) same-minute different-content DOUBLE collision → uniquified (-N), never
#     clobbers a prior timestamped sibling. Uses a fixed-stamp `date` shim so
#     both collisions resolve to the same minute.
# ---------------------------------------------------------------------------
DATEBIN="${TMPROOT}/datebin"; mkdir -p "$DATEBIN"
cat > "${DATEBIN}/date" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "+%Y%m%d-%H%M" ]; then echo "20260902-1200"; else exec /bin/date "$@"; fi
EOF
chmod +x "${DATEBIN}/date"

D3="${TMPROOT}/samemin"
PATH="${DATEBIN}:${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D3" MOCK_MODE=success MOCK_CONTENT="AAA" bash "$INGEST" "$INPUT" >/dev/null 2>&1
PATH="${DATEBIN}:${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D3" MOCK_MODE=success MOCK_CONTENT="BBB" bash "$INGEST" "$INPUT" >/dev/null 2>&1
OUT="$(PATH="${DATEBIN}:${MOCKBIN}:${PATH}" SYNDICATE_TRANSCRIPT_DIR="$D3" MOCK_MODE=success MOCK_CONTENT="CCC" bash "$INGEST" "$INPUT" 2>&1)"; RC=$?
b_intact=$([ "$(cat "${D3}/call-42-20260902-1200.md" 2>/dev/null)" = "BBB" ] && echo yes || echo no)
c_uniq=$([ "$(cat "${D3}/call-42-20260902-1200-1.md" 2>/dev/null)" = "CCC" ] && echo yes || echo no)
if [ "$RC" -eq 0 ] && [ "$b_intact" = yes ] && [ "$c_uniq" = yes ]; then
    ok "i_same_minute_double_collision_no_clobber"
else fail "i_same_minute_double_collision_no_clobber" "rc=$RC b_intact=$b_intact c_uniq=$c_uniq out='$OUT'"; fi

echo ""
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS — ${TOTAL} tests run, ${PASS} passed, 0 failed"; exit 0
else
    echo "FAIL — ${TOTAL} tests run, ${PASS} passed, ${FAIL} failed"
    printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
