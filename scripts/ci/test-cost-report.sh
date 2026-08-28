#!/usr/bin/env bash
# test-cost-report.sh — regression tests for scripts/cost-report.sh
#
# Covers the subagent-discovery fix: subagents live at
#   <project>/<session-id>/subagents/agent-*.jsonl
# not as siblings of the main .jsonl.
#
# Tests:
#   1. POSITIVE  — main + 2 subagents summed; header shows (+2 subagent files)
#   2. NEGATIVE  — second session's subagents NOT counted (still +2, not +3)
#   3. EMPTY     — session with no subagents dir: reports +0, fires SUBAGENT_NOTE
#
# Requires: jq
# Run standalone: bash scripts/ci/test-cost-report.sh
# Called by:     scripts/ci/test.sh (which validate.sh invokes)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COST_REPORT="${REPO_ROOT}/scripts/cost-report.sh"

PASS=0
FAIL=0
FAILURES=()

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() {
    FAIL=$((FAIL + 1))
    local msg="$1${2:+ — $2}"
    FAILURES+=("$msg")
    echo "  FAIL: $msg"
}

# Prerequisite
if ! command -v jq &>/dev/null; then
    echo "SKIP: jq not available — cannot run cost-report tests" >&2
    exit 1
fi

if [ ! -f "$COST_REPORT" ]; then
    echo "SKIP: $COST_REPORT not found" >&2
    exit 1
fi

# Temp fixture dir — cleaned up on exit
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PROJ="${TEST_TMPDIR}/my-project"
SID="session-abc123"
OTHER_SID="session-xyz789"
EMPTY_SID="session-empty"

mkdir -p "${PROJ}"

# Helper: emit a minimal valid assistant JSONL line
# $1=model  $2=input_tokens  $3=output_tokens
make_line() {
    printf '{"type":"assistant","message":{"model":"%s","usage":{"input_tokens":%d,"output_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
        "$1" "$2" "$3"
}

# ===================================================================
# TEST 1: POSITIVE — main + 2 subagents
# ===================================================================
echo ""
echo "--- Test 1: Positive — 2 subagents discovered ---"

make_line "us.anthropic.claude-opus-4-8"               1000 500 > "${PROJ}/${SID}.jsonl"
mkdir -p "${PROJ}/${SID}/subagents"
make_line "us.anthropic.claude-sonnet-4-6"              800 300 > "${PROJ}/${SID}/subagents/agent-1.jsonl"
make_line "us.anthropic.claude-haiku-4-5-20251001-v1:0" 500 200 > "${PROJ}/${SID}/subagents/agent-2.jsonl"

T1="$(bash "${COST_REPORT}" --transcript "${PROJ}/${SID}.jsonl" 2>&1)"

T1_HEADER="$(echo "$T1" | grep 'Transcript:' || true)"
T1_TOTAL_LINE="$(echo "$T1"  | grep 'ON-DEMAND LIST:'  || true)"
T1_ACTUAL_LINE="$(echo "$T1" | grep 'EST. ACTUAL'      || true)"

if [[ "$T1" == *"(+2 subagent files)"* ]]; then
    ok "test1_header_shows_plus2"
else
    fail "test1_header_shows_plus2" "got: '${T1_HEADER}'"
fi

if [[ "$T1" == *"opus"* ]]; then
    ok "test1_opus_model_present"
else
    fail "test1_opus_model_present" "opus not found in output"
fi

if [[ "$T1" == *"sonnet"* ]]; then
    ok "test1_sonnet_model_present"
else
    fail "test1_sonnet_model_present" "sonnet not found in output"
fi

if [[ "$T1" == *"haiku"* ]]; then
    ok "test1_haiku_model_present"
else
    fail "test1_haiku_model_present" "haiku not found in output"
fi

# ON-DEMAND LIST line must show a nonzero dollar amount (matches $X.XX where X > 0)
if echo "$T1_TOTAL_LINE" | grep -qE '\$[0-9]*[1-9][0-9]*\.[0-9]+|\$[0-9]+\.[0-9]*[1-9]'; then
    ok "test1_total_is_nonzero"
else
    fail "test1_total_is_nonzero" "got: '${T1_TOTAL_LINE}'"
fi

# EST. ACTUAL line must be present and show a nonzero dollar amount (factor applied)
if echo "$T1_ACTUAL_LINE" | grep -qE 'EST\. ACTUAL.*\$[0-9]*[1-9][0-9]*\.[0-9]+|EST\. ACTUAL.*\$[0-9]+\.[0-9]*[1-9]'; then
    ok "test1_est_actual_present"
else
    fail "test1_est_actual_present" "got: '${T1_ACTUAL_LINE}'"
fi

if [[ "$T1" != *"No subagent transcripts found"* ]]; then
    ok "test1_no_subagent_note"
else
    fail "test1_no_subagent_note" "SUBAGENT_NOTE fired when it should not have"
fi

# ===================================================================
# TEST 2: NEGATIVE — second session's subagent must NOT be counted
# ===================================================================
echo ""
echo "--- Test 2: Negative — over-count guard (second session isolated) ---"

make_line "us.anthropic.claude-opus-4-8" 9999 9999 > "${PROJ}/${OTHER_SID}.jsonl"
mkdir -p "${PROJ}/${OTHER_SID}/subagents"
make_line "us.anthropic.claude-opus-4-8" 9999 9999 > "${PROJ}/${OTHER_SID}/subagents/agent-9.jsonl"

T2="$(bash "${COST_REPORT}" --transcript "${PROJ}/${SID}.jsonl" 2>&1)"

T2_HEADER="$(echo "$T2" | grep 'Transcript:' || true)"

if [[ "$T2" == *"(+2 subagent files)"* ]]; then
    ok "test2_first_session_still_plus2"
else
    fail "test2_first_session_still_plus2" "got: '${T2_HEADER}'"
fi

if [[ "$T2" != *"(+3 subagent files)"* ]]; then
    ok "test2_second_session_not_counted"
else
    fail "test2_second_session_not_counted" "over-count: second session's subagent was included"
fi

# ===================================================================
# TEST 3: EMPTY — no subagents dir; +0 reported; SUBAGENT_NOTE fires
# ===================================================================
echo ""
echo "--- Test 3: Empty — no subagents dir ---"

make_line "us.anthropic.claude-opus-4-8" 1000 500 > "${PROJ}/${EMPTY_SID}.jsonl"
# intentionally no subagents dir

T3="$(bash "${COST_REPORT}" --transcript "${PROJ}/${EMPTY_SID}.jsonl" 2>&1)"

T3_HEADER="$(echo "$T3" | grep 'Transcript:' || true)"

if [[ "$T3" == *"(+0 subagent files)"* ]]; then
    ok "test3_zero_subagents_reported"
else
    fail "test3_zero_subagents_reported" "got: '${T3_HEADER}'"
fi

if [[ "$T3" == *"No subagent transcripts found"* ]]; then
    ok "test3_subagent_note_fires"
else
    fail "test3_subagent_note_fires" "SUBAGENT_NOTE did not fire; output: $T3"
fi

# ===================================================================
# TEST 4: --per-subagent breakdown (label from attributionAgent + tool count)
# ===================================================================
echo ""
echo "--- Test 4: --per-subagent table ---"

PS_SID="session-persub"
mkdir -p "${PROJ}/${PS_SID}/subagents"
make_line "us.anthropic.claude-opus-4-8" 1000 500 > "${PROJ}/${PS_SID}.jsonl"
{
  printf '{"attributionAgent":"forge","type":"assistant","message":{"model":"us.anthropic.claude-opus-4-8","usage":{"input_tokens":900,"output_tokens":400,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n'
  printf '{"type":"tool_use"}\n'
  printf '{"type":"tool_use"}\n'
} > "${PROJ}/${PS_SID}/subagents/agent-forge1.jsonl"

T4="$(bash "${COST_REPORT}" --transcript "${PROJ}/${PS_SID}.jsonl" --per-subagent 2>&1)"

if [[ "$T4" == *"PER-SUBAGENT"* ]]; then
    ok "test4_persub_header"
else
    fail "test4_persub_header" "no PER-SUBAGENT section; output: $T4"
fi

T4_ROW="$(echo "$T4" | sed -n '/PER-SUBAGENT/,$p' | grep 'forge' || true)"
if [[ -n "$T4_ROW" ]]; then
    ok "test4_persub_label"
else
    fail "test4_persub_label" "forge label not in per-subagent table; output: $T4"
fi

# tool-count column must show 2 (the two tool_use lines) for the forge row
if echo "$T4_ROW" | grep -qE '(^|[[:space:]])2([[:space:]]|$)'; then
    ok "test4_persub_toolcount"
else
    fail "test4_persub_toolcount" "expected tools=2 in row: '${T4_ROW}'"
fi

# ===================================================================
# Summary
# ===================================================================
TOTAL=$((PASS + FAIL))
echo ""
echo "=========================="
if [ "$FAIL" -eq 0 ]; then
    echo "PASS — ${TOTAL} tests run, ${PASS} passed, 0 failed"
    exit 0
else
    echo "FAIL — ${TOTAL} tests run, ${PASS} passed, ${FAIL} failed"
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
        echo "  - ${f}"
    done
    exit 1
fi
