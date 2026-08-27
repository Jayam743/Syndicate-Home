#!/usr/bin/env bash
# test.sh — master test runner for Syndicate CI tests
#
# Discovers and runs every test-*.sh in scripts/ci/ in alphabetical order.
# Exit 0 only when all suites pass.
#
# Recognized by post-tool-test-sentinel.sh — running this script writes the
# push sentinel on success, unlocking Hermes's pre-push gate.
#
# Usage:
#   ./scripts/ci/test.sh           # from repo root
#   bash scripts/ci/test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUITES_RUN=0
SUITES_FAILED=0
FAILED_NAMES=()

for test_script in "${SCRIPT_DIR}"/test-*.sh; do
    [ -f "$test_script" ] || continue
    name="$(basename "$test_script")"
    echo ""
    echo "=== Running: ${name} ==="
    if bash "$test_script"; then
        SUITES_RUN=$((SUITES_RUN + 1))
    else
        SUITES_RUN=$((SUITES_RUN + 1))
        SUITES_FAILED=$((SUITES_FAILED + 1))
        FAILED_NAMES+=("$name")
    fi
done

echo ""
echo "=========================="
echo "Test suites: ${SUITES_RUN} run, $((SUITES_RUN - SUITES_FAILED)) passed, ${SUITES_FAILED} failed"

if [ "${SUITES_FAILED}" -gt 0 ]; then
    echo "Failed suites:"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - $n"
    done
    exit 1
fi

exit 0
