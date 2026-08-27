#!/usr/bin/env bash
# Pre-push test gate — blocks git push unless tests have been run
#
# PreToolUse hook. Wired under a bare "Bash" matcher; this script MUST filter
# internally for `git push` and no-op on every other Bash command — otherwise
# it gates every single Bash call (catastrophic UX).
#
# How it works:
# - A companion PostToolUse hook (post-tool-test-sentinel.sh) writes a sentinel
#   file when tests pass.
# - This hook checks for that sentinel before allowing push.
# - Sentinel expires after 30 minutes (tests must be recent).
#
# Integration branches (kahuna/*, release/*) skip the gate — CI handles them.
#
# On block it emits {"decision":"block","reason":...} and exits 0 (CC block
# contract). Override with PUSH_GATE_DISABLED=1.
set -uo pipefail

# --- B′ INVARIANT (issue #30) — LOAD-BEARING CONTRACT, DO NOT WEAKEN ---
# The sentinel is WORKTREE-KEYED: key = sha1(git toplevel of the push command's
# cwd), file = ~/.syndicate/sentinels/<key>. This is what stops item A's test
# pass from unlocking item B's push under parallel fan-out (the old global
# ~/.syndicate/.test-sentinel let ANY fresh sentinel green-light ANY push).
#
# B′'s guarantee holds ONLY while: fan-out ⇒ each item runs in its OWN worktree.
# If two fanned items share a worktree they share a key, and A's pass unlocks B
# again. #8's fan path MUST assert worktree isolation BEFORE fanning; if it
# cannot guarantee per-item worktrees it MUST forbid the fan. This gate does NOT
# enforce that (out of scope for #30) — it only relies on it.

if [[ "${PUSH_GATE_DISABLED:-0}" == "1" ]]; then
    exit 0
fi

# --- Worktree-keyed sentinel: shared key derivation (B′, issue #30) ---
# Resolve a stable per-worktree key from a command's cwd. The key is the sha1
# of the repo TOPLEVEL (`git -C <cwd> rev-parse --show-toplevel`). Honors an
# explicit `git -C <path>` inside the acted-on command. Prints the key on
# success; prints nothing and returns 1 on failure.
# FAIL CLOSED: callers MUST treat a non-zero return as "no key" and NEVER fall
# back to a shared global sentinel. This function is duplicated verbatim in
# post-tool-test-sentinel.sh and godspeed.sh — keep the three copies in sync.
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

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Only gate actual push commands. Without this the "Bash" matcher would gate
# every Bash call in the session.
if ! printf '%s' "$COMMAND" | grep -qE '^\s*git\s+push'; then
    exit 0
fi

SENTINEL_DIR="${HOME}/.syndicate/sentinels"
MAX_AGE_SECONDS=1800  # 30 minutes

# Allow integration branches through (CI gates them instead). Resolve the branch
# from the push command's cwd, not the hook's ambient pwd.
CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
if [[ "$CURRENT_BRANCH" == kahuna/* ]] || [[ "$CURRENT_BRANCH" == release/* ]]; then
    exit 0
fi

# Resolve the SAME per-worktree key from the push command's cwd. FAIL CLOSED: if
# the worktree can't be resolved, block — a safety gate that fails open is worse
# than useless.
KEY=$(syndicate_sentinel_key "$CWD" "$COMMAND") || {
    printf '{"decision":"block","reason":"Cannot resolve the worktree for this push (no git toplevel from the command cwd) — failing closed. Run the project test tooling in this worktree first, or set PUSH_GATE_DISABLED=1 to override."}'
    exit 0
}
SENTINEL="${SENTINEL_DIR}/${KEY}"

# Opportunistic GC: on every gate check, prune orphan sentinels older than the
# freshness window so dead worktrees don't accumulate files. Exclude the current
# key so the explicit stale-message path below still fires for it.
if [[ -d "$SENTINEL_DIR" ]]; then
    find "$SENTINEL_DIR" -maxdepth 1 -type f ! -name "$KEY" \
        -mmin "+$((MAX_AGE_SECONDS / 60))" -delete 2>/dev/null || true
fi

# Check sentinel exists for THIS worktree.
if [[ ! -f "$SENTINEL" ]]; then
    printf '{"decision":"block","reason":"Cannot push untested code — no test sentinel for this worktree. Run the project test/lint/validate tooling first (Gauntlet writes the per-worktree sentinel on pass). The push will be allowed once tests pass. Set PUSH_GATE_DISABLED=1 to override."}'
    exit 0
fi

# Check sentinel freshness.
SENTINEL_AGE=$(( $(date +%s) - $(stat -c %Y "$SENTINEL" 2>/dev/null || stat -f %m "$SENTINEL" 2>/dev/null || echo 0) ))
if [[ "$SENTINEL_AGE" -gt "$MAX_AGE_SECONDS" ]]; then
    rm -f "$SENTINEL"
    printf '{"decision":"block","reason":"Test sentinel for this worktree is stale (%ss old, max %ss). Re-run tests to create a fresh sentinel before pushing. Set PUSH_GATE_DISABLED=1 to override."}' "$SENTINEL_AGE" "$MAX_AGE_SECONDS"
    exit 0
fi

# Sentinel is fresh — allow push.
exit 0
