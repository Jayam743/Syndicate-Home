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
#   4. PER-SUB   — --per-subagent table: label from attributionAgent + tool count
#   5. DERIVE    — --per-subagent label derived from companion .meta.json agentType
#                  when attributionAgent absent (not "general-purpose" fallback)
#   6. CACHE     — cache tokens priced at cache rates, NOT the input rate (guards the
#                  old ~2x over-report: cache_read=0.50, cache_write=6.25, not input 5)
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
make_line "us.anthropic.claude-sonnet-5[1m]"           800 300 > "${PROJ}/${SID}/subagents/agent-1.jsonl"
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
# TEST 5: --per-subagent label derivation from companion .meta.json
#   When attributionAgent is ABSENT but the companion <transcript>.meta.json
#   carries agentType (the real persona slug), the row must use that persona —
#   NOT fall back to "general-purpose".
# ===================================================================
echo ""
echo "--- Test 5: --per-subagent label derived from meta.json agentType ---"

D_SID="session-derive"
mkdir -p "${PROJ}/${D_SID}/subagents"
make_line "us.anthropic.claude-opus-4-8" 1000 500 > "${PROJ}/${D_SID}.jsonl"
# subagent transcript with NO attributionAgent field ...
{
  printf '{"type":"assistant","message":{"model":"us.anthropic.claude-haiku-4-5-20251001-v1:0","usage":{"input_tokens":700,"output_tokens":250,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n'
  printf '{"type":"tool_use"}\n'
} > "${PROJ}/${D_SID}/subagents/agent-derive1.jsonl"
# ... but a companion .meta.json that carries the persona slug
printf '{"agentType":"cipher","description":"convert doc","spawnDepth":1}\n' \
  > "${PROJ}/${D_SID}/subagents/agent-derive1.meta.json"

T5="$(bash "${COST_REPORT}" --transcript "${PROJ}/${D_SID}.jsonl" --per-subagent 2>&1)"

T5_TABLE="$(echo "$T5" | sed -n '/PER-SUBAGENT/,$p')"

if echo "$T5_TABLE" | grep -q 'cipher'; then
    ok "test5_label_derived_from_meta"
else
    fail "test5_label_derived_from_meta" "cipher not derived from meta.json; output: $T5"
fi

if ! echo "$T5_TABLE" | grep -qE '(^|[[:space:]])general-purpose([[:space:]]|$)'; then
    ok "test5_no_general_purpose_fallback"
else
    fail "test5_no_general_purpose_fallback" "row wrongly fell back to general-purpose; output: $T5"
fi

# ===================================================================
# TEST 6: CACHE-TOKEN PRICING — cache tokens are billed at the cache rates,
#   NOT the input rate. This guards the old ~2x over-report hypothesis (applying the
#   input rate to cache tokens). For Opus: cache_read=0.50, cache_write(5m)=6.25/MTok,
#   vs input=5. So 1,000,000 cache_read tokens must cost $0.50 (not $5.00) and
#   1,000,000 cache_write tokens must cost $6.25 (not $5.00).
# ===================================================================
echo ""
echo "--- Test 6: Cache-token pricing (cache rates, not input rate) ---"

# 1M cache_read tokens, zero input/output — must price at the cache_read rate (0.50).
CR_SID="session-cacheread"
printf '{"type":"assistant","message":{"model":"us.anthropic.claude-opus-4-8[1m]","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":0}}}\n' \
  > "${PROJ}/${CR_SID}.jsonl"

T6R="$(bash "${COST_REPORT}" --transcript "${PROJ}/${CR_SID}.jsonl" 2>&1)"
T6R_TOTAL_LINE="$(echo "$T6R" | grep 'ON-DEMAND LIST:' || true)"

if echo "$T6R_TOTAL_LINE" | grep -q 'ON-DEMAND LIST: \$0\.50'; then
    ok "test6_cache_read_priced_at_cache_rate"
else
    fail "test6_cache_read_priced_at_cache_rate" "expected \$0.50 (cache_read rate, not \$5.00 input); got: '${T6R_TOTAL_LINE}'"
fi

# 1M cache_write tokens, zero input/output — must price at the cache_write(5m) rate (6.25).
CW_SID="session-cachewrite"
printf '{"type":"assistant","message":{"model":"us.anthropic.claude-opus-4-8[1m]","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":1000000}}}\n' \
  > "${PROJ}/${CW_SID}.jsonl"

T6W="$(bash "${COST_REPORT}" --transcript "${PROJ}/${CW_SID}.jsonl" 2>&1)"
T6W_TOTAL_LINE="$(echo "$T6W" | grep 'ON-DEMAND LIST:' || true)"

if echo "$T6W_TOTAL_LINE" | grep -q 'ON-DEMAND LIST: \$6\.25'; then
    ok "test6_cache_write_priced_at_cache_rate"
else
    fail "test6_cache_write_priced_at_cache_rate" "expected \$6.25 (cache_write rate, not \$5.00 input); got: '${T6W_TOTAL_LINE}'"
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
