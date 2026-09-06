#!/usr/bin/env bash
# Worktree-keyed sentinel hook tests — issue #30
# Tests post-tool-test-sentinel.sh, pre-push-test-gate.sh, and godspeed.sh
# by piping crafted JSON payloads directly to the hook files.
#
# SAFETY-CRITICAL: a false negative here ships untested code.
# Tests 2 and 3 are the CRITICAL regression cases for the false-green bug.
#
# Usage: bash scripts/ci/test-sentinel.sh
# Exit 0 = all tests passed; non-zero = at least one failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

WRITER="${REPO_ROOT}/hooks/post-tool-test-sentinel.sh"
GATE="${REPO_ROOT}/hooks/pre-push-test-gate.sh"
GODSPEED_HOOK="${REPO_ROOT}/hooks/godspeed.sh"
SENTINEL_DIR="${HOME}/.syndicate/sentinels"

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); echo "  FAIL: $1"; }

# Returns true (exit 0) iff the string contains a {"decision":"block",...} payload.
# jq 1.6 treats completely empty stdin as valid (exits 0), so we MUST guard on
# non-empty $1 before invoking jq — otherwise every "gate allows" test flips.
is_blocked() {
    local out="$1"
    [[ -n "$out" ]] && printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1
}

# Mirror the hooks' syndicate_sentinel_key function exactly.
sentinel_key_for() {
    local path="$1" toplevel key
    toplevel=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || return 1
    key=$(printf '%s' "$toplevel" | sha1sum | awk '{print $1}')
    [[ -n "$key" ]] || return 1
    printf '%s' "$key"
}

# Unset the gate override so tests reflect real hook behaviour.
unset PUSH_GATE_DISABLED 2>/dev/null || true

# ---------- setup: two throwaway git worktrees ----------
TMPDIR_LOCAL=$(mktemp -d)
WORKTREE_A="${TMPDIR_LOCAL}/repo_a"
WORKTREE_B="${TMPDIR_LOCAL}/repo_b"
mkdir -p "$WORKTREE_A" "$WORKTREE_B"

git -C "$WORKTREE_A" init -q
git -C "$WORKTREE_A" config user.email "gauntlet@syndicate.local"
git -C "$WORKTREE_A" config user.name "Gauntlet"
git -C "$WORKTREE_A" commit --allow-empty -m "init" -q

git -C "$WORKTREE_B" init -q
git -C "$WORKTREE_B" config user.email "gauntlet@syndicate.local"
git -C "$WORKTREE_B" config user.name "Gauntlet"
git -C "$WORKTREE_B" commit --allow-empty -m "init" -q

KEY_A=$(sentinel_key_for "$WORKTREE_A")
KEY_B=$(sentinel_key_for "$WORKTREE_B")

if [[ "$KEY_A" == "$KEY_B" ]]; then
    echo "FATAL: test setup failure — worktrees A and B resolved to the same sentinel key"
    exit 1
fi

mkdir -p "$SENTINEL_DIR"

# Stash any real sentinel for these keys so tests don't inherit dirty state.
BACKUP_A="${TMPDIR_LOCAL}/backup_a"
BACKUP_B="${TMPDIR_LOCAL}/backup_b"
[[ -f "${SENTINEL_DIR}/${KEY_A}" ]] && cp "${SENTINEL_DIR}/${KEY_A}" "$BACKUP_A"
[[ -f "${SENTINEL_DIR}/${KEY_B}" ]] && cp "${SENTINEL_DIR}/${KEY_B}" "$BACKUP_B"
rm -f "${SENTINEL_DIR}/${KEY_A}" "${SENTINEL_DIR}/${KEY_B}"

# Stash godspeed mandate/state so the confidence tests start clean.
MANDATE_FILE="${HOME}/.syndicate/.godspeed"
STATE_FILE="${HOME}/.syndicate/.godspeed-state"
BACKUP_MANDATE="${TMPDIR_LOCAL}/mandate_backup"
BACKUP_STATE="${TMPDIR_LOCAL}/state_backup"
[[ -f "$MANDATE_FILE" ]] && cp "$MANDATE_FILE" "$BACKUP_MANDATE"
[[ -f "$STATE_FILE" ]] && cp "$STATE_FILE" "$BACKUP_STATE"
rm -f "$MANDATE_FILE" "$STATE_FILE"

# Minimal valid transcript for godspeed tests (one user + one assistant msg,
# no tool_use calls, so ACTION="" and TRANSCRIPT_OK=1).
TRANSCRIPT_FILE="${TMPDIR_LOCAL}/transcript.jsonl"
printf '%s\n%s\n' \
    '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"test"}]}}' \
    '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}' \
    > "$TRANSCRIPT_FILE"

cleanup() {
    rm -rf "$TMPDIR_LOCAL"
    rm -f "${SENTINEL_DIR}/${KEY_A}" "${SENTINEL_DIR}/${KEY_B}"
    # Restore any real sentinels.
    [[ -f "$BACKUP_A" ]] && cp "$BACKUP_A" "${SENTINEL_DIR}/${KEY_A}"
    [[ -f "$BACKUP_B" ]] && cp "$BACKUP_B" "${SENTINEL_DIR}/${KEY_B}"
    # Restore godspeed state.
    rm -f "$MANDATE_FILE" "$STATE_FILE"
    [[ -f "$BACKUP_MANDATE" ]] && cp "$BACKUP_MANDATE" "$MANDATE_FILE"
    [[ -f "$BACKUP_STATE" ]] && cp "$BACKUP_STATE" "$STATE_FILE"
}
trap cleanup EXIT

echo ""
echo "=== Sentinel Hook Tests (issue #30) ==="
echo "  Worktree A: ${WORKTREE_A} (key: ${KEY_A:0:8}...)"
echo "  Worktree B: ${WORKTREE_B} (key: ${KEY_B:0:8}...)"
echo ""

# ================================================================
# TEST 1: Writer positive
# ================================================================
echo "--- Test 1: Writer positive ---"
rm -f "${SENTINEL_DIR}/${KEY_A}"

printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_A" | bash "$WRITER"

if [[ -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "1: writer creates A's sentinel for pytest success (exit 0)"
else
    fail "1: writer did NOT create A's sentinel for pytest success"
fi

# ================================================================
# TEST 2 (CRITICAL): False-green regression
# ================================================================
echo ""
echo "--- Test 2 (CRITICAL): False-green regression ---"
echo "    command: 'pytest && git -C <B> log', cwd: A, exit_code: 0"
echo "    Writer MUST key on .cwd (A) and MUST NOT key on git -C B in command."
rm -f "${SENTINEL_DIR}/${KEY_A}" "${SENTINEL_DIR}/${KEY_B}"

printf '{"tool_input":{"command":"pytest && git -C %s log"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_B" "$WORKTREE_A" | bash "$WRITER"

if [[ -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "2a: writer created A's sentinel (cwd=A → correct)"
else
    fail "2a: writer did NOT create A's sentinel (cwd=A, exit 0 — unexpected)"
fi

if [[ ! -f "${SENTINEL_DIR}/${KEY_B}" ]]; then
    pass "2b (CRITICAL): writer did NOT create B's sentinel (git -C B in command ignored by writer — fix confirmed)"
else
    fail "2b (CRITICAL): writer INCORRECTLY created B's sentinel from 'git -C B' substring in command — FALSE-GREEN BUG IS PRESENT"
fi

# ================================================================
# TEST 3 (CRITICAL): Gate isolation — only A sentinel present
# ================================================================
echo ""
echo "--- Test 3 (CRITICAL): Gate isolation ---"
echo "    Only A's sentinel present; gate MUST block B and allow A."
# Ensure only A sentinel exists (written in test 2a).
rm -f "${SENTINEL_DIR}/${KEY_B}"

# 3a: push from B must be BLOCKED
OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$WORKTREE_B" | bash "$GATE")
if printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "3a (CRITICAL): gate BLOCKS push from B when only A's sentinel exists"
else
    fail "3a (CRITICAL): gate did NOT block push from B — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# 3b: push from A must be ALLOWED (no block JSON, exits 0)
OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$WORKTREE_A" | bash "$GATE")
if ! is_blocked "$OUT"; then
    pass "3b (CRITICAL): gate ALLOWS push from A when A's fresh sentinel exists"
else
    fail "3b (CRITICAL): gate incorrectly BLOCKED push from A — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# ================================================================
# TEST 4: Gate git-C precedence (gate honors git -C in push command)
# ================================================================
echo ""
echo "--- Test 4: Gate git-C precedence ---"
echo "    command: 'git -C <A> push', cwd: B, only A sentinel → ALLOWS"
# A's sentinel still present from test 2a/3.
OUT=$(printf '{"tool_input":{"command":"git -C %s push"},"cwd":"%s"}' \
    "$WORKTREE_A" "$WORKTREE_B" | bash "$GATE")
if ! is_blocked "$OUT"; then
    pass "4: gate ALLOWS 'git -C A push' from cwd=B when A's sentinel is present"
else
    fail "4: gate incorrectly BLOCKED 'git -C A push' from cwd=B — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# ================================================================
# TEST 5: Fail-closed scenarios
# ================================================================
echo ""
echo "--- Test 5: Fail-closed ---"

# 5a: writer cwd="" → writes nothing
rm -f "${SENTINEL_DIR}/${KEY_A}" "${SENTINEL_DIR}/${KEY_B}"
COUNT_BEFORE=$(find "$SENTINEL_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
printf '{"tool_input":{"command":"pytest"},"cwd":"","tool_response":{"exit_code":0}}' \
    | bash "$WRITER"
COUNT_AFTER=$(find "$SENTINEL_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [[ "$COUNT_AFTER" -le "$COUNT_BEFORE" ]]; then
    pass "5a: writer with cwd='' writes nothing (fail-closed)"
else
    fail "5a: writer with cwd='' wrote a sentinel — should fail-closed"
fi

# 5b: writer cwd=non-repo → writes nothing
NONREPO="${TMPDIR_LOCAL}/not_a_repo"
mkdir -p "$NONREPO"
COUNT_BEFORE=$(find "$SENTINEL_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$NONREPO" | bash "$WRITER"
COUNT_AFTER=$(find "$SENTINEL_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [[ "$COUNT_AFTER" -le "$COUNT_BEFORE" ]]; then
    pass "5b: writer with cwd=non-repo writes nothing (fail-closed)"
else
    fail "5b: writer with cwd=non-repo wrote a sentinel"
fi

# 5c: writer missing exit_code → default 1, no write
rm -f "${SENTINEL_DIR}/${KEY_A}"
printf '{"tool_input":{"command":"pytest"},"cwd":"%s"}' "$WORKTREE_A" \
    | bash "$WRITER"
if [[ ! -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "5c: writer with missing exit_code writes nothing (defaults to 1 — fail-closed)"
else
    fail "5c: writer with missing exit_code wrote sentinel (should default to failure)"
fi

# 5d: gate cwd="" → BLOCKS
OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":""}' | bash "$GATE")
if printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "5d: gate with cwd='' blocks (fail-closed)"
else
    fail "5d: gate with cwd='' did NOT block — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# 5e: gate cwd=non-repo → BLOCKS
OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$NONREPO" | bash "$GATE")
if printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "5e: gate with cwd=non-repo blocks (fail-closed)"
else
    fail "5e: gate with cwd=non-repo did NOT block — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# ================================================================
# TEST 6: Writer negative (no sentinel written)
# ================================================================
echo ""
echo "--- Test 6: Writer negative ---"

# 6a: exit_code=1 with a recognized test command
rm -f "${SENTINEL_DIR}/${KEY_A}"
printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":1}}' \
    "$WORKTREE_A" | bash "$WRITER"
if [[ ! -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "6a: writer writes nothing on exit_code=1 (test failure)"
else
    fail "6a: writer wrote sentinel on exit_code=1 — should never write on failure"
fi

# 6b: non-test command "ls" with exit_code=0
rm -f "${SENTINEL_DIR}/${KEY_A}"
printf '{"tool_input":{"command":"ls"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_A" | bash "$WRITER"
if [[ ! -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "6b: writer writes nothing for non-test command 'ls' even with exit 0"
else
    fail "6b: writer wrote sentinel for non-test command 'ls'"
fi

# ================================================================
# TEST 7: Stale sentinel → gate blocks and removes it
# ================================================================
echo ""
echo "--- Test 7: Stale sentinel ---"

# Write A's sentinel then backdate it past the 1800s window.
printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_A" | bash "$WRITER"
touch -t 202501010000 "${SENTINEL_DIR}/${KEY_A}"

OUT=$(printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$WORKTREE_A" | bash "$GATE")
if printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "7a: gate BLOCKS when sentinel is stale (>1800s)"
else
    fail "7a: gate did NOT block on stale sentinel — output: $(printf '%s' "$OUT" | head -c 200)"
fi

if [[ ! -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "7b: gate removes the stale sentinel on block"
else
    fail "7b: gate did NOT remove the stale sentinel"
fi

# ================================================================
# TEST 8: GC — orphan pruned, current key preserved
# ================================================================
echo ""
echo "--- Test 8: Orphan GC ---"

# Plant an orphan sentinel (fake key) backdated well past the 30-min GC window.
ORPHAN_KEY="deadbeef0000000000000000000000000000dead"
ORPHAN_FILE="${SENTINEL_DIR}/${ORPHAN_KEY}"
touch "$ORPHAN_FILE"
touch -t 202501010000 "$ORPHAN_FILE"

# Write A's sentinel (fresh) and run gate for A.
printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_A" | bash "$WRITER"
printf '{"tool_input":{"command":"git push"},"cwd":"%s"}' "$WORKTREE_A" | bash "$GATE" > /dev/null

if [[ ! -f "$ORPHAN_FILE" ]]; then
    pass "8a: stale orphan sentinel pruned on gate run (GC works)"
else
    fail "8a: stale orphan sentinel NOT pruned by GC"
    rm -f "$ORPHAN_FILE"
fi

if [[ -f "${SENTINEL_DIR}/${KEY_A}" ]]; then
    pass "8b: current-key sentinel NOT pruned by GC (excluded from GC sweep)"
else
    fail "8b: current-key sentinel was incorrectly pruned by GC"
fi

# ================================================================
# TEST 9: Godspeed confidence (80% with sentinel, 40% without)
# ================================================================
echo ""
echo "--- Test 9: Godspeed confidence ---"
# Confidence formula: BAR_PCT = turns*100/20.
# We set STATE_FILE to 8 (hook increments to 9), giving BAR_PCT=45.
# 45 > 40 (no-sentinel floor) → block.  45 <= 80 (with-sentinel ceiling) → allow.
# This distinguishes the two thresholds cleanly.

# Arm the mandate (required to reach the confidence check).
mkdir -p "$(dirname "$MANDATE_FILE")"
printf 'godspeed\n' > "$MANDATE_FILE"

# 9a: sentinel for CWD present → 80% confidence → BAR_PCT(45) <= 80 → ALLOW
printf '{"tool_input":{"command":"pytest"},"cwd":"%s","tool_response":{"exit_code":0}}' \
    "$WORKTREE_A" | bash "$WRITER"
printf '8\n' > "$STATE_FILE"
OUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$WORKTREE_A" "$TRANSCRIPT_FILE" \
    | bash "$GODSPEED_HOOK")
if ! is_blocked "$OUT"; then
    pass "9a: godspeed ALLOWS at 80% confidence when sentinel exists for cwd"
else
    REASON=$(printf '%s' "$OUT" | jq -r '.reason // ""')
    if printf '%s' "$REASON" | grep -qi "confidence decayed"; then
        fail "9a: godspeed blocked due to confidence decay — 80% threshold used as 40% (sentinel present but not read)"
    else
        fail "9a: godspeed blocked for unexpected reason: $(printf '%s' "$REASON" | head -c 120)"
    fi
fi

# 9b: NO sentinel for CWD → 40% confidence → BAR_PCT(45) > 40 → BLOCK
rm -f "${SENTINEL_DIR}/${KEY_A}"
printf '8\n' > "$STATE_FILE"
OUT=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$WORKTREE_A" "$TRANSCRIPT_FILE" \
    | bash "$GODSPEED_HOOK")
if printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    REASON=$(printf '%s' "$OUT" | jq -r '.reason // ""')
    if printf '%s' "$REASON" | grep -qi "confidence decayed"; then
        pass "9b: godspeed BLOCKS at 40% confidence (no sentinel) — correct floor behaviour"
    else
        fail "9b: godspeed blocked but for wrong reason: $(printf '%s' "$REASON" | head -c 120)"
    fi
else
    fail "9b: godspeed did NOT block without sentinel — 40% floor not enforced — output: $(printf '%s' "$OUT" | head -c 200)"
fi

# ================================================================
# Summary
# ================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo "==========================="
if [[ "$FAIL" -eq 0 ]]; then
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
