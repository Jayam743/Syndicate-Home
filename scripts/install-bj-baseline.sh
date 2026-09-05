#!/usr/bin/env bash
set -euo pipefail

# install-bj-baseline.sh — install the vendored BJ core-workflow skills (home box).
#
# On the home (Pro subscription) machine the BJ layer is NOT fetched from BJ's live
# upstream — it comes from the frozen snapshot vendored in vendor/bj-baseline/. This
# script links (or copies, with --copy) those vendored skills into ~/.claude/skills/.
#
# NON-DESTRUCTIVE: any skill you ALREADY have in ~/.claude/skills/ is skipped, never
# overwritten (yours and Syndicate's own skills are left untouched). Idempotent.
#
# Usage:
#   ./scripts/install-bj-baseline.sh          # symlink vendored BJ skills (default)
#   ./scripts/install-bj-baseline.sh --copy   # copy instead of symlink

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_SKILLS="${REPO_ROOT}/vendor/bj-baseline/skills"
VENDOR_AXIOMS="${REPO_ROOT}/vendor/bj-baseline/WAVE_AXIOMS.md"
CLAUDE_DIR="${HOME}/.claude"
SKILLS_DIR="${CLAUDE_DIR}/skills"

MODE="symlink"
if [ "${1:-}" = "--copy" ]; then
    MODE="copy"
fi

if [ ! -d "$VENDOR_SKILLS" ]; then
    echo "ERROR: vendored BJ skills not found at ${VENDOR_SKILLS}" >&2
    echo "Are you on the home/lean-pro branch with vendor/bj-baseline/ present?" >&2
    exit 1
fi

mkdir -p "$SKILLS_DIR"

echo "━━━ Installing vendored BJ baseline (${MODE}) ━━━"

INSTALLED=0
SKIPPED=0
for skill_dir in "${VENDOR_SKILLS}/"*/; do
    [ -d "$skill_dir" ] || continue
    name="$(basename "$skill_dir")"
    target="${SKILLS_DIR}/${name}"

    # Non-destructive: never clobber an existing skill (yours, BJ's, or Syndicate's).
    if [ -e "$target" ] || [ -L "$target" ]; then
        echo "  ○ SKIP: ${name}/ (already present — not overwritten)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [ "$MODE" = "copy" ]; then
        cp -r "$skill_dir" "$target"
    else
        ln -s "$skill_dir" "$target"
    fi
    echo "  ✓ ${name}/"
    INSTALLED=$((INSTALLED + 1))
done

# WAVE_AXIOMS.md — layered mode references it. Install only if absent (non-destructive).
if [ -f "$VENDOR_AXIOMS" ]; then
    axioms_target="${CLAUDE_DIR}/WAVE_AXIOMS.md"
    if [ -e "$axioms_target" ] || [ -L "$axioms_target" ]; then
        echo "  ○ SKIP: WAVE_AXIOMS.md (already present)"
    else
        if [ "$MODE" = "copy" ]; then
            cp "$VENDOR_AXIOMS" "$axioms_target"
        else
            ln -s "$VENDOR_AXIOMS" "$axioms_target"
        fi
        echo "  ✓ WAVE_AXIOMS.md"
    fi
fi

echo ""
echo "Done: ${INSTALLED} installed, ${SKIPPED} skipped (already present)."
echo "settings.reference.json (vendor/bj-baseline/) documents which hooks BJ registers —"
echo "it is a REFERENCE, not a drop-in. Merge hooks into ~/.claude/settings.json by hand."
