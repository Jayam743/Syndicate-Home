#!/usr/bin/env bash
# scripts/ci/test-fan-eligibility.sh
# Unit tests for scripts/lib/fan-eligibility.js — safety-critical predicate.
# Globbed by scripts/ci/test.sh via the test-*.sh pattern.
#
# Exit 0 = all assertions green.
# Exit 1 = at least one assertion failed (or node absent).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_JS="${SCRIPT_DIR}/test-fan-eligibility.js"

echo "=== fan-eligibility unit tests ==="
echo ""

if ! command -v node &>/dev/null; then
  echo "FAIL: node not found in PATH — install Node.js to run fan-eligibility tests"
  exit 1
fi

NODE_VERSION="$(node --version 2>/dev/null)"
echo "  node: ${NODE_VERSION}"
echo "  test: ${TEST_JS}"
echo ""

node "${TEST_JS}"
