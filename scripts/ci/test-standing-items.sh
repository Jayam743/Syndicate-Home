#!/usr/bin/env bash
# test-standing-items.sh — tests for the prospective standing-items mechanism (Opt 1′)
#
# Asserts: undated-reject write gate, past/future due detection, repo-scope
# filtering, close mark-in-place drop-out, and the >5 due-item overflow cap.
# Uses a temp store (STANDING_ITEMS_STORE) + a fixed repo scope
# (STANDING_ITEMS_REPO) so it never touches the real store.
#
# Usage: bash scripts/ci/test-standing-items.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLI="${REPO_ROOT}/scripts/standing-items.sh"

PASS=0
FAIL=0
FAILURES=()
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL: $1"; }

TMPD=$(mktemp -d)
export STANDING_ITEMS_STORE="${TMPD}/standing-items.md"
export STANDING_ITEMS_REPO="repo-under-test"
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

PAST=$(date -d '10 days ago' +%F)
FUTURE=$(date -d '10 days' +%F)

echo ""
echo "=== Standing Items Tests (Opt 1′) ==="
echo "  store: ${STANDING_ITEMS_STORE}  scope: ${STANDING_ITEMS_REPO}"

# (a) write-time gate: add WITHOUT --due must fail nonzero
echo ""
echo "--- (a) undated-reject gate ---"
if "$CLI" add "no due date here" >/dev/null 2>&1; then
    fail "a: add WITHOUT --due should exit nonzero (undated-reject gate)"
else
    pass "a: add WITHOUT --due fails nonzero"
fi

# (b) past due date → appears in `due`
echo ""
echo "--- (b) past due date surfaces ---"
"$CLI" add --due "$PAST" "past-due-item-B" >/dev/null
if "$CLI" due | grep -q "past-due-item-B"; then
    pass "b: past-due item appears in due"
else
    fail "b: past-due item did NOT appear in due"
fi

# (c) future due date → does NOT appear in `due`
echo ""
echo "--- (c) future due date hidden ---"
"$CLI" add --due "$FUTURE" "future-item-C" >/dev/null
if "$CLI" due | grep -q "future-item-C"; then
    fail "c: future-dated item INCORRECTLY appeared in due"
else
    pass "c: future-dated item does not appear in due"
fi

# (d) repo scope filters correctly
echo ""
echo "--- (d) repo-scope filter ---"
"$CLI" add --due "$PAST" --repo other-repo "scoped-elsewhere-D" >/dev/null
if "$CLI" due | grep -q "scoped-elsewhere-D"; then
    fail "d1: item scoped to a different repo INCORRECTLY appeared in due"
else
    pass "d1: item scoped to a different repo is filtered out"
fi
"$CLI" add --due "$PAST" --repo repo-under-test "scoped-here-D" >/dev/null
if "$CLI" due | grep -q "scoped-here-D"; then
    pass "d2: item scoped to the current repo appears in due"
else
    fail "d2: item scoped to the current repo did NOT appear in due"
fi

# (e) close flips the item and it drops out of due/list
echo ""
echo "--- (e) close marks-in-place + drops out ---"
OUT=$("$CLI" add --due "$PAST" "closeme-item-E")
ID=$(printf '%s' "$OUT" | grep -oE 'si-[0-9a-f]+' | head -1)
"$CLI" close "$ID" >/dev/null
if "$CLI" due | grep -q "closeme-item-E"; then
    fail "e1: closed item still appears in due"
else
    pass "e1: closed item dropped from due"
fi
if "$CLI" list | grep -q "closeme-item-E"; then
    fail "e2: closed item still appears in list (open)"
else
    pass "e2: closed item dropped from list"
fi
if grep -qE "^- \[x\] ${ID} .*\| closed:" "$STANDING_ITEMS_STORE"; then
    pass "e3: line flipped to [x] with closed: appended (mark-in-place, not deleted)"
else
    fail "e3: closed line not flipped/annotated in place"
fi

# (f) >5 due items → overflow collapses to the escalating line (cap works)
echo ""
echo "--- (f) overflow cap ---"
rm -f "$STANDING_ITEMS_STORE"
for i in 1 2 3 4 5 6 7; do
    "$CLI" add --due "$PAST" "overflow-item-${i}" >/dev/null
done
OUT=$("$CLI" due)
if printf '%s' "$OUT" | grep -q "standing items due — run: standing-items.sh list"; then
    pass "f1: >5 due items collapse to the escalating line"
else
    fail "f1: overflow escalating line not produced"
fi
LINES=$(printf '%s\n' "$OUT" | grep -c .)
if [ "$LINES" -le "$((4 + 1))" ]; then
    pass "f2: due output is capped (${LINES} lines, never dumps the whole store)"
else
    fail "f2: due output NOT capped (${LINES} lines)"
fi

# Summary
TOTAL=$((PASS + FAIL))
echo ""
echo "==========================="
if [ "$FAIL" -eq 0 ]; then
    echo "PASSED: ${TOTAL} tests run, ${PASS} passed, 0 failed"
    exit 0
else
    echo "FAILED: ${TOTAL} tests run, ${PASS} passed, ${FAIL} failed"
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - ${f}"
    done
    exit 1
fi
