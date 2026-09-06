#!/usr/bin/env bash
# UserPromptSubmit preflight (issue #43) — converts the main loop's SILENT skips of
# doctrine Step 0.5 (Scribe recraft) and Step 1.5 (recall) into STATED decisions.
#
# #4 gave the JS workflows a deterministic recall/scribe precondition. The MAIN LOOP
# had no equivalent, so ~12 findings/month were "Scribe skipped, not stated" / "recall
# never fired, skip not disclosed". Doctrine ALREADY requires stating the decision in
# the plan line — this hook makes it un-ignorable by injecting a reminder into context
# whenever the request looks SUBSTANTIAL. A false fire is a harmless extra reminder; a
# miss lets a silent skip through — so this biases toward firing.
#
# UserPromptSubmit contract: stdin is JSON with .prompt; stdout on exit 0 is added to
# the model's context for this turn. We print the reminder only for substantial prompts.
set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)

# Nothing to check.
[ -n "$PROMPT" ] || exit 0

# Normalize to lowercase for matching; measure length.
lc=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')
len=${#PROMPT}

# SKIP (trivial / already-scoped): a bare slash-command, the resume trigger, short
# affirmations/thanks, or a very short prompt with no action verb. These don't need a
# recraft/recall decision surfaced.
first_word=$(printf '%s' "$lc" | awk '{print $1}')
case "$first_word" in
  /*) exit 0 ;;                                  # explicit slash command
  continue|thanks|thank|yes|no|ok|okay|yep|nope|godspeed|halt!|stop) exit 0 ;;
esac

# Action / substance signals — if ANY match, treat as substantial.
SUBSTANTIAL_RE='build|implement|fix|refactor|debug|investigat|diagnos|analy[sz]e|review|audit|design|migrat|optimi[sz]e|add |create|write |rework|figure out|root[- ]cause|why is|make .* (better|work)|ship|deploy'

is_substantial=0
if printf '%s' "$lc" | grep -qE "$SUBSTANTIAL_RE"; then
  is_substantial=1
elif [ "$len" -gt 200 ]; then
  is_substantial=1                               # long prompt → likely multi-part
elif [ "$(printf '%s' "$PROMPT" | grep -oE '\?' | wc -l)" -gt 1 ]; then
  is_substantial=1                               # multiple questions/asks
fi

[ "$is_substantial" -eq 1 ] || exit 0

cat <<'EOF'
[Syndicate preflight — doctrine Steps 0.5 & 1.5] This request looks substantial.
Before acting, STATE both decisions in your plan line (silence is not a valid skip):
  • Scribe: used | skipped — <reason: already-precise / already-enumerated / trivial>
  • Recall: ran | skipped — <reason: single-purpose / user-supplied context / trivial>
If it's a wiring/functional decision, also state the Decision-review disposition.
EOF
exit 0
