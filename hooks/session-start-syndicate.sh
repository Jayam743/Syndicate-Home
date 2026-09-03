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

set -uo pipefail

# Locate the Syndicate repo (this script lives in <repo>/hooks/ or is symlinked)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
DOCTRINE="${REPO_ROOT}/config/doctrine.md"

# If we can't find the doctrine, fail silent (don't break the session)
[ -f "$DOCTRINE" ] || exit 0

# --- Godspeed inter-session expiry (Design 1) --------------------------------
# Decay (godspeed.sh) is INTRA-session: confidence erodes turn-by-turn.
# Expiry (here) is INTER-session: a mandate should not silently survive a fresh
# session boot. Orthogonal mechanisms. SessionStart stdout is injected into
# context, so any warning below is kept short.
#
# Read the CC hook payload; .source tells us how the session started.
INPUT=$(cat 2>/dev/null || true)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo unknown)

MANDATE_FILE="${HOME}/.syndicate/.godspeed"
STATE_FILE="${HOME}/.syndicate/.godspeed-state"
GODSPEED_TTL_SECONDS=28800  # 8h wall-clock backstop
GODSPEED_NOTICE=""

disarm_mandate() {
    rm -f "$MANDATE_FILE" "$STATE_FILE"
}

# PostCompact owns the compact path — do nothing to the mandate on compact.
# (Regression armor: SessionStart can fire with source=compact.)
if [[ "$SOURCE" != "compact" && -f "$MANDATE_FILE" ]]; then
    case "$SOURCE" in
        startup|clear)
            # Fresh boot / cleared context — a mandate from a prior session must
            # not carry over silently. Auto-disarm.
            disarm_mandate
            GODSPEED_NOTICE="⚠ Godspeed mandate auto-DISARMED (session ${SOURCE}). Re-arm with \"godspeed\" if intended."
            ;;
        *)
            # resume / unknown → KEEP the mandate, but warn loudly.
            GODSPEED_NOTICE="⚠ Godspeed mandate KEPT across session ${SOURCE} — still ARMED. Say HALT! to revoke."
            ;;
    esac
fi

# Wall-time TTL backstop — ALWAYS runs while a mandate exists, regardless of
# source (survivors from resume/unknown still age out). Fails CLOSED.
if [[ "$SOURCE" != "compact" && -f "$MANDATE_FILE" ]]; then
    ARMED=$(grep -m1 '^armed=' "$MANDATE_FILE" 2>/dev/null | cut -d= -f2- || true)
    ARMED_EPOCH=$(date -d "$ARMED" +%s 2>/dev/null || true)
    NOW_EPOCH=$(date +%s)
    if [[ -z "$ARMED" || -z "$ARMED_EPOCH" ]]; then
        # Missing / unparseable armed timestamp — cannot prove freshness → disarm.
        disarm_mandate
        GODSPEED_NOTICE="⚠ Godspeed mandate DISARMED — armed timestamp missing/unparseable (fail-closed)."
    elif (( ARMED_EPOCH > NOW_EPOCH )); then
        # Future-dated (clock skew / tampering) — cannot trust → disarm.
        disarm_mandate
        GODSPEED_NOTICE="⚠ Godspeed mandate DISARMED — armed timestamp is in the future (fail-closed)."
    elif (( NOW_EPOCH - ARMED_EPOCH > GODSPEED_TTL_SECONDS )); then
        disarm_mandate
        GODSPEED_NOTICE="⚠ Godspeed mandate EXPIRED (>8h old) — auto-DISARMED. Re-arm with \"godspeed\" if intended."
    fi
fi

# Reflect the post-check state in the banner.
GODSPEED_STATE="inactive"
if [ -f "$MANDATE_FILE" ]; then
    GODSPEED_STATE="ARMED"
fi

# Check for a resumable pipeline
PIPELINE_STATE=""
if [ -f "${HOME}/.syndicate/pipelines/current.json" ]; then
    PIPELINE_STATE="⚡ A pipeline is in progress — check ~/.syndicate/pipelines/current.json to resume."
fi

# --- Prospective standing items (Opt 1′) -------------------------------------
# Surface DUE prospective-memory items at session boot. Reuses the compact guard
# above: skip on compact (already in context, re-dumping is noise). Fail-soft —
# absent script/store → no-op silently.
STANDING_BANNER=""
if [[ "$SOURCE" != "compact" ]]; then
    SI_SCRIPT="${HOME}/.syndicate/scripts/standing-items.sh"
    if [ -x "$SI_SCRIPT" ]; then
        SI_DUE=$("$SI_SCRIPT" due 2>/dev/null || true)
        [ -n "$SI_DUE" ] && STANDING_BANNER=$(printf '📌 Standing items due:\n%s' "$SI_DUE")
    fi
fi

# --- Recall BM25 index self-heal (Invariant A: SessionStart-only cadence) ------
# Keep scripts/recall.sh's FTS5/BM25 index fresh WITHOUT any external scheduler.
# Incremental (only files newer than the last index) once the index exists; the
# one-time cold build (373 MB) happens on first boot. BOTH run BACKGROUNDED so the
# boot path never blocks, timeout-bounded, and fully QUIET — SessionStart stdout is
# injected into context, so every byte here goes to a log file, none to stdout.
# Fail-soft: absent python3/FTS5/helper → no-op (recall's grep fallback covers it).
# The .db lives under ~/.syndicate (ext4), never on the /mnt/c WSL mount.
if [[ "$SOURCE" != "compact" ]]; then
    INDEX_PY="${REPO_ROOT}/scripts/lib/recall-index.py"
    RECALL_DB="${SYNDICATE_RECALL_DB:-${HOME}/.syndicate/kb/recall-index.db}"
    PROJECTS_DIR="${SYNDICATE_PROJECTS_DIR:-${HOME}/.claude/projects}"
    RECALL_LOG="${HOME}/.syndicate/logs/recall-index.log"
    if [ -f "$INDEX_PY" ] && [ -d "$PROJECTS_DIR" ] && command -v python3 >/dev/null 2>&1 \
       && python3 "$INDEX_PY" probe >/dev/null 2>&1; then
        mkdir -p "$(dirname "$RECALL_DB")" "$(dirname "$RECALL_LOG")" 2>/dev/null || true
        if command -v timeout >/dev/null 2>&1; then
            RUN_IDX=(timeout 600 python3 "$INDEX_PY" index --db "$RECALL_DB" --projects "$PROJECTS_DIR")
        else
            RUN_IDX=(python3 "$INDEX_PY" index --db "$RECALL_DB" --projects "$PROJECTS_DIR")
        fi
        # Detach so the indexer survives the hook returning; all output → log only.
        nohup "${RUN_IDX[@]}" >>"$RECALL_LOG" 2>&1 &
        disown 2>/dev/null || true
    fi
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
${GODSPEED_NOTICE}
${PIPELINE_STATE}
${STANDING_BANNER}

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
