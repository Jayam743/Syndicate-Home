#!/usr/bin/env bash
# Decision-Review trigger predicate — single source of truth.
#
# Decides whether a commit REQUIRES a `Decision-Review:` trailer, based purely on
# the set of staged (changed) files. Shared by BOTH callers so they cannot drift:
#   - hooks/git/commit-msg   (the git-native gate — enforces / aborts commit)
#   - skills/precheck        (report-only mirror — reminds, never blocks)
#
# Input:  staged file paths, one per line, on STDIN.
#         If STDIN is empty, falls back to `git diff --cached --name-only`.
# Output: prints a single token to STDOUT: "REQUIRED" or "NOT_REQUIRED".
# Exit:   0 = trailer REQUIRED
#         1 = trailer NOT required
set -uo pipefail

# Wiring surface: files whose change alters FUTURE / system behavior. A change is
# only ever a candidate trigger if at least one staged path matches this.
WIRING_RE='^(config/|hooks/|agents/|skills/|scripts/ci/|.*settings.*\.json$|CLAUDE\.md$)'

# Docs-only / test-only files never trigger, even inside the wiring surface.
# NOTE: config/*.md is WIRING (doctrine / models / toolkit / permissions) and is
# deliberately NOT a docs exclusion — only README.md and docs/ are docs.
is_excluded() {
    local f="$1"
    # docs-only
    case "$f" in
        README.md | */README.md) return 0 ;;
        docs/*) return 0 ;;
    esac
    # test-only
    if printf '%s' "$f" | grep -qE '(^tests?/|_test\.|\.test\.|\.spec\.)'; then
        return 0
    fi
    return 1
}

matches_wiring() {
    printf '%s' "$1" | grep -qE "$WIRING_RE"
}

main() {
    local files
    files="$(cat 2>/dev/null || true)"
    if [[ -z "${files//[[:space:]]/}" ]]; then
        files="$(git diff --cached --name-only 2>/dev/null || true)"
    fi

    local required=1 f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        if matches_wiring "$f" && ! is_excluded "$f"; then
            required=0
            break
        fi
    done <<< "$files"

    if [[ "$required" -eq 0 ]]; then
        echo "REQUIRED"
        return 0
    fi
    echo "NOT_REQUIRED"
    return 1
}

main "$@"
