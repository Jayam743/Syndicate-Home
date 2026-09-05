#!/usr/bin/env bash
# Guardrail: the active Claude Code `availableModels` allowlist must contain every
# model enum Syndicate agents/workflows request.
#
# WHY: the real cost leak was the harness `availableModels` allowlist missing "haiku",
# so `model:"haiku"` spawns silently fell BACK to the session default (Opus 4.8) instead
# of resolving to Haiku — every mechanical-band spawn quietly billed at Opus rates. It's
# fixed in ~/.claude/settings.json (now ["opus","sonnet","haiku"]), but that file is
# hand-managed GLOBAL config that can silently regress on a reinstall / new machine. This
# test catches exactly that regression.
#
# REQUIRED set = {sonnet, haiku}: mechanical band spawns request `haiku`, formula band
# requests `sonnet` (see config/models.md — "Main-loop / Agent-tool spawns" table). `opus`
# is the session default and is always available, so it is NOT in the required set. This is
# a clearly-commented hardcoded list rather than a models.md parse: the mapping lives in a
# prose table that is not cleanly machine-parseable, so we anchor to it by reference.
#
# The check is a GUARDRAIL, not a universal precondition: if the settings file or the
# `availableModels` key is ABSENT (standalone install / a box without global settings),
# it SKIPS cleanly rather than hard-failing. When the key IS present, a missing required
# model FAILS LOUD listing what's missing.
#
# Settings path: $SYNDICATE_CC_SETTINGS if set, else ~/.claude/settings.json. The override
# exists so the self-tests below can drive the core check against synthetic fixtures.
set -uo pipefail

# REQUIRED enums — see config/models.md (mechanical->haiku, formula->sonnet; opus=default).
REQUIRED=(sonnet haiku)

PASS=0; FAIL=0; SKIP=0; FAILURES=()
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }
skip() { echo "  SKIP: $1 — $2"; SKIP=$((SKIP+1)); }

command -v python3 >/dev/null 2>&1 || { echo "  SKIP: python3 unavailable"; echo ""; echo "PASS — 0 cases (0 passed, 1 skipped, 0 failed)"; exit 0; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

echo "--- model allowlist guardrail ---"

# Core check. Reads availableModels from the given settings path and echoes a status:
#   ABSENT            — file or key missing (caller SKIPS)
#   OK                — every REQUIRED enum present
#   MISSING:<a,b,...>  — key present but these REQUIRED enums are absent (caller FAILS)
allowlist_status() {
    local settings="$1"; shift
    SETTINGS="$settings" REQ="$*" python3 - <<'PYEOF'
import json, os, sys
settings = os.environ["SETTINGS"]
required = os.environ["REQ"].split()
try:
    with open(settings) as fh:
        data = json.load(fh)
except (OSError, ValueError):
    print("ABSENT"); sys.exit(0)
if "availableModels" not in data or data["availableModels"] is None:
    print("ABSENT"); sys.exit(0)
have = set(data["availableModels"])
missing = [m for m in required if m not in have]
print("OK" if not missing else "MISSING:" + ",".join(missing))
PYEOF
}

# ---------------------------------------------------------------------------
# (main) The ACTIVE settings allowlist must contain the required enums.
#        absent -> skip clean; complete -> pass; missing -> FAIL LOUD.
# ---------------------------------------------------------------------------
ACTIVE="${SYNDICATE_CC_SETTINGS:-${HOME}/.claude/settings.json}"
STATUS="$(allowlist_status "$ACTIVE" "${REQUIRED[@]}")"
case "$STATUS" in
    ABSENT)
        skip "active_allowlist_superset" "no availableModels in ${ACTIVE} (standalone/global-less box — guardrail N/A)" ;;
    OK)
        ok "active_allowlist_superset" ;;
    MISSING:*)
        fail "active_allowlist_superset" "active availableModels in ${ACTIVE} is MISSING required enum(s): ${STATUS#MISSING:} — silent Opus fallback risk" ;;
    *)
        fail "active_allowlist_superset" "unexpected status '$STATUS'" ;;
esac

# ---------------------------------------------------------------------------
# (a) present-and-complete -> OK (the fixed-settings shape).
# ---------------------------------------------------------------------------
printf '{"availableModels":["opus","sonnet","haiku"]}\n' > "${TMPROOT}/complete.json"
S="$(allowlist_status "${TMPROOT}/complete.json" "${REQUIRED[@]}")"
if [ "$S" = "OK" ]; then ok "a_present_complete_ok"
else fail "a_present_complete_ok" "status='$S' (expected OK)"; fi

# ---------------------------------------------------------------------------
# (b) present-but-missing-haiku -> the exact regression -> MISSING flagged.
# ---------------------------------------------------------------------------
printf '{"availableModels":["opus","sonnet"]}\n' > "${TMPROOT}/no-haiku.json"
S="$(allowlist_status "${TMPROOT}/no-haiku.json" "${REQUIRED[@]}")"
if [ "$S" = "MISSING:haiku" ]; then ok "b_missing_haiku_flagged"
else fail "b_missing_haiku_flagged" "status='$S' (expected MISSING:haiku)"; fi

# ---------------------------------------------------------------------------
# (c) file absent -> ABSENT (caller skips, never hard-fails).
# ---------------------------------------------------------------------------
S="$(allowlist_status "${TMPROOT}/does-not-exist.json" "${REQUIRED[@]}")"
if [ "$S" = "ABSENT" ]; then ok "c_file_absent_skips"
else fail "c_file_absent_skips" "status='$S' (expected ABSENT)"; fi

# ---------------------------------------------------------------------------
# (d) key absent (file present, no availableModels) -> ABSENT (skip clean).
# ---------------------------------------------------------------------------
printf '{"model":"opus"}\n' > "${TMPROOT}/no-key.json"
S="$(allowlist_status "${TMPROOT}/no-key.json" "${REQUIRED[@]}")"
if [ "$S" = "ABSENT" ]; then ok "d_key_absent_skips"
else fail "d_key_absent_skips" "status='$S' (expected ABSENT)"; fi

echo ""
TOTAL=$((PASS+FAIL+SKIP))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS — ${TOTAL} cases (${PASS} passed, ${SKIP} skipped, 0 failed)"; exit 0
else
    echo "FAIL — ${TOTAL} cases (${PASS} passed, ${SKIP} skipped, ${FAIL} failed)"
    printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
