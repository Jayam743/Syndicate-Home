#!/usr/bin/env bash
# env-preflight.sh — Syndicate env-drift preflight (iteration 1: ansible-core ONLY)
#
# THE SCAR: "local env was wrong; GitLab/CI had the right env." An agent chased a
# phantom bug because it trusted a stale local ansible instead of the authoritative
# declared pin. Invariant B: for DRIFT-PRONE facts, authoritative-external >
# local-cache > in-context-recollection — retrieve-and-assert, never trust local
# blindly.
#
# KEY design correction (Loki): do NOT build a declared env.manifest — a manifest is
# itself a drift-prone cache that rebuilds the sin. Read the EXISTING authoritative
# home instead: the declared `ansible-core` pin in requirements*.txt.
#
# USAGE: an env-touching agent (Titan) — or the operator — runs this at TASK-START,
# in a target repo, before doing ansible work. No-op on non-ansible repos.
#
# Dispositions (one line each, machine-greppable prefix `env-preflight:`):
#   PASS        live SATISFIES declared pin   exit 0
#   DRIFT       both present, out of policy    exit 3  (BLOCKS the env-touching task)
#   UNVERIFIED  ansible absent / no pin        exit 0  (proceed under DECLARED, LOGGED
#                                                       uncertainty — logged to audit)
#
# PASS is OPERATOR-AWARE and SEMANTIC — not raw string equality (that produced false
# DRIFT: `>=2.15` vs live `2.21.0` SATISFIES the floor; `==2.21` vs `2.21.0` is the
# SAME version in a different trailing-zero shape). Disposition by operator:
#   ==  exact   : PASS iff live semantically EQUALS declared; else DRIFT (direction).
#   >= / ~=     : PASS iff live is AT-OR-ABOVE the floor; DRIFT (local-STALE) only when
#                 live is BELOW it. (~= is treated as a pure floor in iteration 1 —
#                 the compatible-release UPPER bound is NOT enforced yet; see comment.)
#   X.Y.*  wild : PASS iff live is within the `X.Y.` prefix series; else DRIFT.
#
# CRITICAL boundary (Loki 5a): "ansible installed + pin present but out of policy" =
# DRIFT (exit nonzero). "ansible absent / pin unreadable" = UNVERIFIED (exit 0 +
# logged). Misrouting drift as unverified would let drift proceed — get this right.
#
# Env overrides:
#   ENV_PREFLIGHT_ANSIBLE_SOURCE=<file>   point at the pin source for ambiguous cases
#   ENV_PREFLIGHT_LOG=<file>              audit-log path (tests point this at a temp)
#   ENV_PREFLIGHT_LIB_ONLY=1              define helpers then return WITHOUT running
#                                         main (so ver_ge/ver_eq are unit-testable)

set -euo pipefail

EXIT_DRIFT=3

AUDIT_LOG="${ENV_PREFLIGHT_LOG:-${HOME}/.syndicate/ledger/env-preflight.log}"

log_unverified() {
    # Append a timestamped audit line (create dir/file if needed). Fail-soft: never
    # let a logging problem turn a proceed into a crash.
    local reason="$1"
    local dir
    dir="$(dirname "$AUDIT_LOG")"
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\t%s\tUNVERIFIED\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(pwd)" "$reason" >> "$AUDIT_LOG" 2>/dev/null || true
}

# --- Semantic version helpers (portable, sort -V) ---------------------------
# ver_eq A B — semantically EQUAL, so trailing-zero shape doesn't matter
#   (2.21 == 2.21.0 == 2.21.0.0). Normalize by stripping trailing `.0` groups, then
#   compare the normalized forms.
ver_eq() {
    local a b
    a="$(printf '%s' "$1" | sed -E 's/(\.0+)+$//')"
    b="$(printf '%s' "$2" | sed -E 's/(\.0+)+$//')"
    [ "$a" = "$b" ]
}

# ver_ge A B — true when A >= B numerically. Idiom: sort A and B with `sort -V`;
#   A >= B exactly when the SMALLER (first line) is B — i.e. B sorts first, so A is at
#   or above it. The equal case is short-circuited up front (sort -V orders "2.21" and
#   "2.21.0" as distinct even though they're the same release, so ver_eq covers that
#   shape gap at the call sites where "at" must PASS).
ver_ge() {
    [ "$1" = "$2" ] && return 0
    local first
    first="$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)"
    [ "$first" = "$2" ]
}

# drift_direction LIVE DECLARED — echo local-ahead when live is at/above declared,
# else local-STALE (the inverse-trap: local behind, CI right, phantom-bug chase).
drift_direction() {
    if ver_ge "$1" "$2"; then
        echo "local-ahead"
    else
        echo "local-STALE"
    fi
}

# --- 1. Auto-detect scope: is this an ansible repo? --------------------------
# An ansible repo = ansible.cfg present, OR an ansible/ dir, OR a requirements*.txt
# that mentions ansible-core.
is_ansible_repo() {
    [ -f "ansible.cfg" ] && return 0
    [ -d "ansible" ] && return 0
    local f
    for f in requirements*.txt; do
        [ -f "$f" ] || continue
        grep -qi 'ansible-core' "$f" && return 0
    done
    return 1
}

# --- 2. Authoritative target = the EXISTING declared pin ---------------------
# Parse the ansible-core OPERATOR + version from requirements*.txt (==, >=, ~=), also
# preserving a trailing `.*` wildcard on the version. Emits "<op> <versionspec>" on one
# line (first hit wins). The declared pin IS the authoritative home — we do not invent
# a new store. An explicit source override wins for ambiguous cases.
parse_declared_pin() {
    local file="$1"
    grep -iE '^[[:space:]]*ansible-core[[:space:]]*(==|>=|~=)' "$file" 2>/dev/null \
        | head -1 \
        | sed -E 's/^[[:space:]]*ansible-core[[:space:]]*(==|>=|~=)[[:space:]]*([0-9][0-9.]*\*?).*/\1 \2/' \
        || true
}

# LIB-ONLY guard: when sourced with ENV_PREFLIGHT_LIB_ONLY=1, expose the helpers above
# for direct unit-testing and return BEFORE running any main logic. `return` works when
# sourced; the `exit 0` fallback covers an accidental direct invocation with the flag.
if [ -n "${ENV_PREFLIGHT_LIB_ONLY:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

if ! is_ansible_repo; then
    # No-op on non-ansible repos (Syndicate itself included).
    exit 0
fi

PIN_RAW=""
if [ -n "${ENV_PREFLIGHT_ANSIBLE_SOURCE:-}" ]; then
    if [ -r "$ENV_PREFLIGHT_ANSIBLE_SOURCE" ]; then
        PIN_RAW="$(parse_declared_pin "$ENV_PREFLIGHT_ANSIBLE_SOURCE")"
    else
        echo "env-preflight: UNVERIFIED — declared-pin source unreadable: ${ENV_PREFLIGHT_ANSIBLE_SOURCE}"
        log_unverified "source unreadable: ${ENV_PREFLIGHT_ANSIBLE_SOURCE}"
        exit 0
    fi
else
    for f in requirements*.txt; do
        [ -f "$f" ] || continue
        PIN_RAW="$(parse_declared_pin "$f")"
        if [ -n "$PIN_RAW" ]; then
            break
        fi
    done
fi

if [ -z "$PIN_RAW" ]; then
    # Ansible repo, but no parseable pin found → UNVERIFIED (not DRIFT).
    echo "env-preflight: UNVERIFIED — no parseable ansible-core pin found in requirements*.txt"
    log_unverified "no parseable ansible-core pin"
    exit 0
fi

# Split "<op> <versionspec>" into operator + declared version.
DECLARED_OP="${PIN_RAW%% *}"
DECLARED="${PIN_RAW##* }"

# --- 3. Live value: the ACTIVE ansible-core version --------------------------
# Loki's scar: a system ansible 2.15 may shadow a ci venv 2.21. Assert the ACTIVE
# one — whatever `ansible --version` on PATH resolves to.
if ! command -v ansible >/dev/null 2>&1; then
    echo "env-preflight: UNVERIFIED — ansible not installed / not on PATH"
    log_unverified "ansible not installed"
    exit 0
fi

# `ansible --version` prints a line like: "ansible [core 2.21.0]" (older: "core 2.9").
# Match the first line carrying "core" followed by a version, extract the version.
LIVE="$(ansible --version 2>/dev/null \
    | grep -iE 'core[^0-9]*[0-9]' \
    | head -1 \
    | sed -E 's/.*core[^0-9]*([0-9][0-9.]*).*/\1/' \
    || true)"

if [ -z "$LIVE" ]; then
    echo "env-preflight: UNVERIFIED — could not parse ansible-core version from 'ansible --version'"
    log_unverified "unparseable ansible --version output"
    exit 0
fi

# --- 4. Compare — operator-aware, 3 dispositions -----------------------------
# Wildcard `X.Y.*` — PASS iff live falls within the `X.Y.` prefix series.
case "$DECLARED" in
    *\*)
        prefix="${DECLARED%\*}"     # e.g. "2.21.*" -> "2.21."
        base="${prefix%.}"          # e.g. "2.21." -> "2.21"
        case "$LIVE" in
            "$prefix"*)
                echo "env-preflight: PASS — ansible-core ${LIVE} within declared wildcard series ${DECLARED}"
                exit 0
                ;;
        esac
        dir="$(drift_direction "$LIVE" "$base")"
        echo "env-preflight: DRIFT — ansible-core live=${LIVE} vs declared=${DECLARED} (${dir})"
        exit "$EXIT_DRIFT"
        ;;
esac

case "$DECLARED_OP" in
    ">="|"~=")
        # Floor / compatible-release. ITERATION-1 SIMPLIFICATION: `~=` is treated as a
        # pure floor (like `>=`) — the compatible-release UPPER bound is NOT enforced
        # yet. Under-enforcing the ceiling is the SAFE (proceed) direction here.
        # local-ahead of a floor is COMPLIANT, not drift; DRIFT only when BELOW floor.
        if ver_ge "$LIVE" "$DECLARED" || ver_eq "$LIVE" "$DECLARED"; then
            echo "env-preflight: PASS — ansible-core ${LIVE} satisfies declared ${DECLARED_OP}${DECLARED}"
            exit 0
        fi
        echo "env-preflight: DRIFT — ansible-core live=${LIVE} vs declared=${DECLARED_OP}${DECLARED} (local-STALE)"
        exit "$EXIT_DRIFT"
        ;;
    *)
        # Exact `==`. PASS on SEMANTIC equality (2.21 == 2.21.0); else DRIFT + direction.
        if ver_eq "$LIVE" "$DECLARED"; then
            echo "env-preflight: PASS — ansible-core ${LIVE} matches declared ${DECLARED}"
            exit 0
        fi
        dir="$(drift_direction "$LIVE" "$DECLARED")"
        echo "env-preflight: DRIFT — ansible-core live=${LIVE} vs declared=${DECLARED} (${dir})"
        exit "$EXIT_DRIFT"
        ;;
esac
