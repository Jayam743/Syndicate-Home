#!/usr/bin/env bash
# SessionStart hook — activates the Syndicate self-dispatch system
#
# This is what makes Syndicate a SELF-SYSTEM rather than a set of tools waiting
# to be called. It injects the dispatch doctrine into the session context at
# startup, so the session classifies and routes EVERY request automatically —
# in ACTIVATED repos, without the user typing /route.
#
# Wiring:
#   - Standalone mode: the installer registers this GLOBALLY in
#     ~/.claude/settings.json under hooks.SessionStart.
#   - Layered mode (BJ's workflow present): Syndicate does NOT touch BJ's shared
#     ~/.claude/settings.json. Each repo opts in by running `syndicate-activate`,
#     which adds this hook to that repo's ./.claude/settings.local.json (Claude
#     Code's git-ignored personal layer). So self-dispatch fires only in repos
#     that have been activated.

set -euo pipefail

# Locate the Syndicate repo (this script lives in <repo>/hooks/ or is symlinked)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
DOCTRINE="${REPO_ROOT}/config/doctrine.md"

# If we can't find the doctrine, fail silent (don't break the session)
[ -f "$DOCTRINE" ] || exit 0

# Check for an active Godspeed mandate
GODSPEED_STATE="inactive"
if [ -f "${HOME}/.syndicate/.godspeed" ]; then
    GODSPEED_STATE="ARMED"
fi

# Check for a resumable pipeline
PIPELINE_STATE=""
if [ -f "${HOME}/.syndicate/pipelines/current.json" ]; then
    PIPELINE_STATE="⚡ A pipeline is in progress — check ~/.syndicate/pipelines/current.json to resume."
fi

# Emit the activation context. SessionStart hook stdout is injected into context.
cat << EOF
═══════════════════════════════════════════════════════════
SYNDICATE ACTIVE — self-dispatch mode engaged
═══════════════════════════════════════════════════════════

You are the front door. On EVERY user request, run the Syndicate
dispatch doctrine BEFORE acting: classify → pick path → show the
one-line plan → act (or auto-act if Godspeed is armed).

Do NOT wait for the user to type /route. Routing is your default.

The user's flow is: /engage (BJ's workflow) → /syndicate (layer this on
top) → then just talk. If they run /syndicate, re-affirm this mode. If a
session started cold (before this hook), /syndicate activates it manually.

Godspeed: ${GODSPEED_STATE}
${PIPELINE_STATE}

The full dispatch doctrine is at:
  ${DOCTRINE}

READ IT NOW if not already in context, then apply it every turn.
Quick version of the decision tree:
  fuzzy idea → Muse | broken(unknown) → investigation workflow
  goal-no-plan → goalseek | 4+ issues → campaign
  implement/fix → pipeline workflow | review → review workflow
  test/ship/infra/secrets/track/message/convert → that agent directly
  trivial/question → just answer

Gates that ALWAYS fire (even under Godspeed): prod, secrets, precheck.
═══════════════════════════════════════════════════════════
EOF

exit 0
