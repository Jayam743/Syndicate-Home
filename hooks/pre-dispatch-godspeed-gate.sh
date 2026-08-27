#!/usr/bin/env bash
# Pre-dispatch Godspeed gate — branch-allowlist layer for autonomous mutation
#
# PreToolUse hook. Wired under the bare "Bash" matcher; this script MUST filter
# internally (mandate present? mutating verb?) and no-op otherwise — a bare
# "Bash" matcher fires on EVERY Bash call.
#
# TRUST INVERSION (read this before editing):
#   pre-push-test-gate TRUSTS kahuna/*, release/* and lets them push (CI gates
#   those integration branches). THIS gate DISTRUSTS main/master/prod/etc. for
#   AUTONOMOUS mutation: under a Godspeed mandate it will only allow a mutating
#   command once it has PROVEN the current branch is NOT a protected branch.
#   Both are correct at their own scope — one is a release-flow trust, the other
#   is an autonomy-flow distrust.
#
# This gate is ADDITIVE and only active while a mandate exists. It does NOT
# duplicate the prod/deploy keyword net in godspeed.sh ABSOLUTE_GATES (that is
# the last-line, always-on net). This layer asks a different question: "can we
# prove we're on a safe branch before letting the mandate auto-run a mutation?"
#
# On block it emits {"decision":"block","reason":...} and exits 0 (CC block
# contract — never a bare exit 1). Override with GODSPEED_GATE_DISABLED=1.
set -uo pipefail

if [[ "${GODSPEED_GATE_DISABLED:-0}" == "1" ]]; then
    # Explicit operator override — stand down.
    exit 0
fi

MANDATE_FILE="${HOME}/.syndicate/.godspeed"

# Gate is only active under a mandate. No mandate → nothing to enforce.
if [[ ! -f "$MANDATE_FILE" ]]; then
    exit 0
fi

INPUT=$(cat 2>/dev/null || true)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# --- MUTATING_VERBS ----------------------------------------------------------
# The set of command shapes that mutate durable state and therefore must not run
# autonomously on a protected branch without proof of a safe branch.
# MAINTENANCE RITUAL: adding a new mutating tool means adding its pattern here.
# ABSOLUTE_GATES (godspeed.sh) is the last-line net, NOT a substitute for keeping
# this list current.
MUTATING_VERBS=(
    'git[[:space:]]+push'
    'git[[:space:]]+reset'
    'git[[:space:]]+rebase'
    'rm[[:space:]]'
    'aws[[:space:]].*[[:space:]](rb|delete|delete-.*|terminate|terminate-.*|rm)([[:space:]]|$)'
    'terraform[[:space:]]+apply'
    'terraform[[:space:]]+destroy'
    'kubectl[[:space:]]+delete'
    'helm[[:space:]]'
    'gh[[:space:]]+repo[[:space:]]+delete'
    'glab[[:space:]].*[[:space:]]delete'
)

IS_MUTATING=0
for verb in "${MUTATING_VERBS[@]}"; do
    if printf '%s' "$COMMAND" | grep -qE -- "$verb"; then
        IS_MUTATING=1
        break
    fi
done

# Non-mutating command → allow (early exit). The mandate governs it elsewhere.
if [[ "$IS_MUTATING" -eq 0 ]]; then
    exit 0
fi

# --- prove_non_prod_branch ---------------------------------------------------
# Fail CLOSED: we must be able to PROVE we are on a non-protected branch. Any
# inability to prove (not a worktree, git error, empty, detached HEAD) → block.
checkpoint() {
    jq -nc --arg r "$1" '{decision:"block",reason:$r}'
    exit 0
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    checkpoint "Godspeed active + mutating command detected, but this is not a git worktree — cannot prove a safe (non-prod) branch. Checkpointing — run this manually, or say HALT! to revoke the mandate."
fi

BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$BR" || "$BR" == "HEAD" ]]; then
    # Empty or detached HEAD — cannot prove which branch we're on.
    checkpoint "Godspeed active + mutating command detected, but the branch could not be determined (detached HEAD or git error) — cannot prove a safe (non-prod) branch. Checkpointing — run this manually, or say HALT! to revoke the mandate."
fi

# Protected-branch allowlist check (case-insensitive).
shopt -s nocasematch
PROTECTED=0
case "$BR" in
    main|master|prod|production|trunk|release/*|hotfix/*|kahuna/*)
        PROTECTED=1
        ;;
esac
shopt -u nocasematch

if [[ "$PROTECTED" -eq 1 ]]; then
    checkpoint "Godspeed active + mutating command on protected branch '${BR}' — the mandate does NOT authorize autonomous mutation here. Checkpointing — run this manually, switch to a feature branch, or say HALT! to revoke the mandate."
fi

# Proven non-prod branch — allow the mutation under the mandate.
exit 0
