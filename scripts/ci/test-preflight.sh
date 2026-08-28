#!/usr/bin/env bash
# Regression test for hooks/user-prompt-preflight.sh (issue #43).
# Verifies it fires the Scribe/recall reminder on substantial prompts and stays
# SILENT on trivial / slash-command / short-question / empty prompts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../hooks/user-prompt-preflight.sh"
PASS=0; FAIL=0; FAILURES=()
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

# $1=name  $2=prompt  $3=expect (fire|silent)
run() {
  local out; out="$(printf '{"prompt":%s}' "$(printf '%s' "$2" | jq -Rs .)" | bash "$HOOK" 2>&1)"
  if [ "$3" = "fire" ]; then
    if printf '%s' "$out" | grep -q "Syndicate preflight"; then ok "$1"; else fail "$1" "expected reminder, got: '${out}'"; fi
  else
    if [ -z "$out" ]; then ok "$1"; else fail "$1" "expected SILENT, got: '${out}'"; fi
  fi
}

echo "--- user-prompt-preflight.sh ---"
run "substantial_implement" "implement the cost governor and fix the fan dispatch bug" fire
run "substantial_investigate" "why is the deploy pipeline crashing on staging" fire
run "substantial_long" "$(printf 'please %.0swork ' {1..60})" fire
run "trivial_thanks" "thanks!" silent
run "trivial_affirm" "yes" silent
run "slash_command" "/continue" silent
run "short_question" "what is this file" silent
run "resume_continue" "continue" silent
run "empty_prompt" "" silent

echo ""
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  echo "PASS — ${TOTAL} tests run, ${PASS} passed, 0 failed"; exit 0
else
  echo "FAIL — ${TOTAL} tests run, ${PASS} passed, ${FAIL} failed"
  printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
