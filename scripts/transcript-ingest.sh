#!/usr/bin/env bash
# transcript-ingest.sh — convert a pasted document/transcript to markdown and land it
# in the canonical transcript dir (non-destructive, idempotent).
#
# Resolution order for the destination dir:
#   1. $SYNDICATE_TRANSCRIPT_DIR (env)
#   2. contents of ~/.syndicate/transcript-dir (a one-line file holding an abs path)
#   3. fallback ~/.syndicate/transcripts/
#
# The resolved dest is ECHOED on every run so a file never silently lands somewhere
# unexpected. Never overwrites an existing transcript.
#
# Usage: transcript-ingest.sh <path>
set -euo pipefail

TAG="[transcript-ingest]"
# Generous ceiling so a huge file (call-35 was 21MB) can't hang forever.
CONVERT_TIMEOUT="${TRANSCRIPT_INGEST_TIMEOUT:-600}"

block() { echo "${TAG} BLOCK: $*" >&2; exit 1; }
warn()  { echo "${TAG} WARN: $*" >&2; }
note()  { echo "${TAG} $*"; }

# --- Resolve destination dir ---
resolve_dest() {
    if [ -n "${SYNDICATE_TRANSCRIPT_DIR:-}" ]; then
        printf '%s\n' "$SYNDICATE_TRANSCRIPT_DIR"
        return
    fi
    local dirfile="${HOME}/.syndicate/transcript-dir"
    if [ -f "$dirfile" ]; then
        local line
        line="$(head -1 "$dirfile" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        if [ -n "$line" ]; then
            printf '%s\n' "$line"
            return
        fi
    fi
    printf '%s\n' "${HOME}/.syndicate/transcripts"
}

# --- Args ---
[ "$#" -ge 1 ] || block "no input path given (usage: transcript-ingest.sh <path>)"
INPUT="$1"

DEST="$(resolve_dest)"
DEST="${DEST%/}"
note "dest → ${DEST}"

# --- Validate input ---
[ -e "$INPUT" ] || block "input path does not exist: ${INPUT}"
[ -f "$INPUT" ] || block "input is not a regular file: ${INPUT}"
[ -r "$INPUT" ] || block "input is not readable: ${INPUT}"

# --- Extension advisory ---
BASENAME="$(basename "$INPUT")"
EXT_LOWER="$(printf '%s' "${BASENAME##*.}" | tr '[:upper:]' '[:lower:]')"
case "$EXT_LOWER" in
    docx|doc|pptx|ppt|xlsx|pdf|rtf|odt) ;;
    *) warn "non-document extension '.${EXT_LOWER}' — attempting anyway (empty output is blocked, but non-empty output is not a guarantee of a clean conversion)" ;;
esac

# --- Sanitize output name (filesystem safety only; no call-number parsing) ---
STEM="${BASENAME%.*}"
SAFE_STEM="$(printf '%s' "$STEM" | tr -c 'A-Za-z0-9._-' '_')"
[ -n "$SAFE_STEM" ] || SAFE_STEM="transcript"
OUT_NAME="${SAFE_STEM}.md"

# --- Ensure markitdown is present ---
command -v markitdown >/dev/null 2>&1 || block "markitdown not found on PATH (pip install markitdown)"

# --- Convert to a tmp file (use -o so a failure can't leave a 0-byte target) ---
TMP="$(mktemp "${TMPDIR:-/tmp}/transcript-ingest.XXXXXX.md")"
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

rc=0
if command -v timeout >/dev/null 2>&1; then
    timeout "$CONVERT_TIMEOUT" markitdown "$INPUT" -o "$TMP" || rc=$?
else
    markitdown "$INPUT" -o "$TMP" || rc=$?
fi

if [ "$rc" -eq 124 ]; then
    block "markitdown timed out after ${CONVERT_TIMEOUT}s on ${INPUT} — cleaned up, nothing written"
fi
if [ "$rc" -ne 0 ]; then
    block "markitdown failed (exit ${rc}) on ${INPUT} — cleaned up, nothing written"
fi
if [ ! -s "$TMP" ]; then
    block "markitdown produced empty output for ${INPUT} — cleaned up, nothing written"
fi

# --- Dest dir (local output dir; creation expected) ---
mkdir -p "$DEST"

TARGET="${DEST}/${OUT_NAME}"

# --- Collision handling (non-destructive, idempotent) ---
if [ -e "$TARGET" ]; then
    new_sha="$(sha256sum "$TMP" | awk '{print $1}')"
    old_sha="$(sha256sum "$TARGET" | awk '{print $1}')"
    if [ "$new_sha" = "$old_sha" ]; then
        note "skipped-identical: ${TARGET} already holds this exact content (idempotent re-paste)"
        note "input: ${INPUT}"
        note "output: ${OUT_NAME}"
        note "disposition: skipped-identical"
        exit 0
    fi
    STAMP="$(date +%Y%m%d-%H%M)"
    TARGET="${DEST}/${SAFE_STEM}-${STAMP}.md"
    # Same-minute different-content collisions: never clobber a prior sibling —
    # skip if an existing sibling is byte-identical, else uniquify with a counter.
    n=0
    while [ -e "$TARGET" ]; do
        if [ "$new_sha" = "$(sha256sum "$TARGET" | awk '{print $1}')" ]; then
            note "skipped-identical: ${TARGET} already holds this exact content (idempotent re-paste)"
            note "input: ${INPUT}"
            note "disposition: skipped-identical"
            exit 0
        fi
        n=$((n + 1))
        TARGET="${DEST}/${SAFE_STEM}-${STAMP}-${n}.md"
    done
    cp "$TMP" "$TARGET"
    note "collision: '${OUT_NAME}' exists with DIFFERENT content — wrote timestamped copy instead"
    note "existing (untouched): ${DEST}/${OUT_NAME}"
    note "new: ${TARGET}"
    note "input: ${INPUT}"
    note "disposition: collision-timestamped"
    exit 0
fi

cp "$TMP" "$TARGET"
note "input: ${INPUT}"
note "output: $(basename "$TARGET")"
note "path: ${TARGET}"
note "disposition: converted"
