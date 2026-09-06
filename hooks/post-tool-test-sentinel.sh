#!/usr/bin/env bash
# Post-tool test sentinel — writes the sentinel file when tests pass.
#
# PostToolUse hook. Wired under a bare "Bash" matcher, so this script filters
# internally for test/lint/validate commands and no-ops on everything else.
# The sentinel unlocks pre-push-test-gate.sh (Hermes can push once tests pass).
#
# PostToolUse hooks cannot block — this one only writes the sentinel, so it
# emits no decision JSON. Reads the CC payload as JSON on STDIN
# (.tool_input.command + the tool exit info); writes only on success.
#
# Recognized: pytest, python -m pytest, npm test, npx vitest, make test/lint,
# ./scripts/ci/{validate,test}.sh, ruff check, cargo test, go test, bun test,
# mvn test.
set -uo pipefail

# --- Worktree-keyed sentinel: shared key derivation (B′, issue #30) ---
# Resolve a stable per-worktree key from a command's cwd. The key is the sha1
# of the repo TOPLEVEL (`git -C <cwd> rev-parse --show-toplevel`). Honors an
# explicit `git -C <path>` inside the acted-on command. Prints the key on
# success; prints nothing and returns 1 on failure.
# FAIL CLOSED: callers MUST treat a non-zero return as "no key" and NEVER fall
# back to a shared global sentinel. This function is duplicated verbatim in
# pre-push-test-gate.sh and godspeed.sh — keep the three copies in sync.
syndicate_sentinel_key() {
    local cwd="$1" cmd="${2:-}" base gitc toplevel key
    # Honor an explicit `git -C <path>` in the command (takes precedence over cwd).
    gitc=$(printf '%s\n' "$cmd" \
        | grep -oE '(^|[[:space:]])git[[:space:]]+-C[[:space:]]+[^[:space:]]+' \
        | head -n1 | grep -oE '[^[:space:]]+$' || true)
    gitc=${gitc%\"}
    gitc=${gitc#\"}
    if [[ -n "$gitc" ]]; then
        base="$gitc"
    else
        base="$cwd"
    fi
    [[ -n "$base" ]] || return 1
    toplevel=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -n "$toplevel" ]] || return 1
    if command -v sha1sum >/dev/null 2>&1; then
        key=$(printf '%s' "$toplevel" | sha1sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        key=$(printf '%s' "$toplevel" | shasum | awk '{print $1}')
    else
        return 1
    fi
    [[ -n "$key" ]] || return 1
    printf '%s' "$key"
}

INPUT=$(cat 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
EXIT_CODE=$(printf '%s' "$INPUT" | jq -r '.tool_response.exit_code // .tool_result.exit_code // 1' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only fire for test/lint/validate commands.
TEST_PATTERN='(pytest|python[0-9.]* -m pytest|npm test|npx vitest|make (test|lint|check)|\./scripts/ci/(validate|test)\.sh|ruff check|cargo test|go test|mvn test|bun test)'
if ! printf '%s' "$COMMAND" | grep -qE "$TEST_PATTERN"; then
    exit 0
fi

# Only mark the sentinel on explicit success. A missing/unparseable exit code
# resolves to 1 above (fail-closed): the sentinel is written ONLY when the
# resolved exit code is exactly 0.
if [[ "$EXIT_CODE" != "0" ]]; then
    exit 0
fi

# Resolve the per-worktree key from the payload's .cwd ONLY — pass "" as the
# command so `git -C <path>` inside it is IGNORED here. Rationale (Athena, #30,
# CRITICAL): the writer marks "tests ran HERE", and tests execute in .cwd no
# matter what the command text mentions. Honoring a `git -C /other` substring
# (e.g. `pytest && git -C /other log`) would let a pass in worktree A write
# worktree B's sentinel and green-light B's UNTESTED push — the exact false-green
# B′ exists to close. The GATE keeps git -C precedence (a `git -C /X push` really
# acts on /X). This is also the cwd-misattribution fix: payload .cwd, not the
# hook's ambient pwd. FAIL CLOSED: no key resolved → write nothing (no fallback).
KEY=$(syndicate_sentinel_key "$CWD" "") || exit 0

SENTINEL_DIR="${HOME}/.syndicate/sentinels"
SENTINEL="${SENTINEL_DIR}/${KEY}"
mkdir -p "$SENTINEL_DIR"

# Metadata lives in the file BODY (informational); the KEY is the filename.
# branch/cwd are resolved from the command's cwd, not the hook's ambient pwd.
cat > "$SENTINEL" <<EOF
passed=$(date -Iseconds)
command=$(printf '%s' "$COMMAND" | head -c 120)
cwd=$CWD
branch=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached")
EOF

exit 0
