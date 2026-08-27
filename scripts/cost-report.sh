#!/usr/bin/env bash
# cost-report.sh — compute per-model cost of a Claude Code session from its transcript
#
# The model CAN'T see /cost (that's a client-side command). But the transcript
# records usage + model on every assistant message, so we compute cost ourselves —
# and get something /cost doesn't: a per-MODEL breakdown. That's the number that
# answers "how much was Opus specifically" — the metric for whether the
# delegation discipline is actually reducing main-loop Opus spend.
#
# Usage:
#   cost-report.sh                      # newest transcript in the current project
#   cost-report.sh --transcript PATH    # a specific .jsonl
#   cost-report.sh --project SLUG       # newest in ~/.claude/projects/<slug>/
#   cost-report.sh --append "label"     # also append a dated line to the cost ledger
#   cost-report.sh --kind build|operate # tag session kind in ledger line
#
# Rates are per MILLION tokens (Bedrock ~ first-party).
# NOTE: The flat rate table previously overshot ~2x on high-cache sessions because
# it treated all cache tokens as cache-write (1.25x input). Now split into:
#   cache_read  ~ 0.1x input rate
#   cache_write ~ 1.25x input rate
# The [1m] 1M-context premium is also accounted for (1.25x base rates).
#
# READ-ONLY except the optional cost-ledger append.

set -u

PROJECTS="${HOME}/.claude/projects"
COST_LEDGER="${HOME}/.syndicate/ledger/costs.md"
TRANSCRIPT=""
PROJECT=""
APPEND_LABEL=""
NOW=""
KIND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript) TRANSCRIPT="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --append) APPEND_LABEL="$2"; shift 2 ;;
    --date) NOW="$2"; shift 2 ;;
    --kind) KIND="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Resolve transcript: explicit > project slug > newest in cwd's project dir
if [ -z "$TRANSCRIPT" ]; then
  if [ -n "$PROJECT" ]; then
    dir="${PROJECTS}/${PROJECT}"
  else
    # slugify cwd the way Claude Code does: / -> -
    slug="$(pwd | sed 's#/#-#g')"
    dir="${PROJECTS}/${slug}"
    [ -d "$dir" ] || dir="$(ls -dt "${PROJECTS}"/*/ 2>/dev/null | head -1)"
  fi
  TRANSCRIPT="$(ls -t "${dir%/}"/*.jsonl 2>/dev/null | head -1)"
fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "cost-report: no transcript found" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "cost-report: jq required" >&2; exit 1; }

# Per-model $/MTok rates: input | output | cache_read | cache_write(5m).
# Matched by substring on the model id (Bedrock ids carry version suffixes).
# [1m] suffix = 1M-context premium at 1.25x base rates.
rate() { # $1=model-id  -> echoes "in out cread cwrite"
  case "$1" in
    *opus*\[1m\]*)  echo "6.25 31.25 0.625 7.8125" ;;
    *opus*)         echo "5 25 0.5 6.25" ;;
    *sonnet*\[1m\]*) echo "3.75 18.75 0.375 4.6875" ;;
    *sonnet*)       echo "3 15 0.3 3.75" ;;
    *haiku*)        echo "1 5 0.1 1.25" ;;
    *)              echo "5 25 0.5 6.25" ;;  # unknown -> assume Opus (conservative)
  esac
}

# Collect all transcript files: main + this session's subagent transcripts.
TRANSCRIPTS=("$TRANSCRIPT")
SUBAGENT_NOTE=""
TRANSCRIPT_DIR="$(dirname "$TRANSCRIPT")"
SESSION_ID="$(basename "$TRANSCRIPT" .jsonl)"

# Subagent transcripts live under a PER-SESSION folder:
#   <project>/<session-id>/subagents/agent-*.jsonl
# The old `-maxdepth 1` glob looked for them as SIBLINGS of the main .jsonl —
# where they never are — so it matched nothing and silently excluded ALL
# delegated (subagent) cost. Scope discovery to THIS session's folder so we
# recover subagent cost WITHOUT summing other sessions' subagents (over-count).
SUBAGENT_DIR="${TRANSCRIPT_DIR}/${SESSION_ID}/subagents"
if [ -d "$SUBAGENT_DIR" ]; then
  while IFS= read -r -d '' subfile; do
    # Skip if it's the main transcript itself (defensive; it lives one level up)
    if [ "$subfile" != "$TRANSCRIPT" ]; then
      TRANSCRIPTS+=("$subfile")
    fi
  done < <(find "$SUBAGENT_DIR" -maxdepth 1 \( -name "agent-*.jsonl" -o -name "task-*.jsonl" \) -print0 2>/dev/null)
fi

if [ "${#TRANSCRIPTS[@]}" -eq 1 ]; then
  SUBAGENT_NOTE="NOTE: Only main transcript processed. No subagent transcripts found (looked in <session-id>/subagents/agent-*.jsonl)."
fi

# Sum tokens per model out of all transcripts, compute cost, emit a table + totals.
# jq groups assistant messages by model and sums each usage field.
SUMMARY="$(jq -rs '
  [ .[] | select(.type=="assistant") | .message
    | select(.model != null and .model != "<synthetic>" and .usage != null)
    | {model: .model,
       in:   (.usage.input_tokens // 0),
       out:  (.usage.output_tokens // 0),
       cr:   (.usage.cache_read_input_tokens // 0),
       cw:   (.usage.cache_creation_input_tokens // 0)} ]
  | group_by(.model)
  | map({model: .[0].model,
         in:  (map(.in)  | add),
         out: (map(.out) | add),
         cr:  (map(.cr)  | add),
         cw:  (map(.cw)  | add)})
  | .[] | "\(.model)\t\(.in)\t\(.out)\t\(.cr)\t\(.cw)"
' "${TRANSCRIPTS[@]}" 2>/dev/null)"

if [ -z "$SUMMARY" ]; then
  echo "cost-report: no usage data in transcript(s)" >&2
  exit 1
fi

echo "=== COST REPORT ==="
echo "Transcript: $(basename "$TRANSCRIPT") (+$((${#TRANSCRIPTS[@]} - 1)) subagent files)"
echo ""
printf "%-40s %10s %10s %8s\n" "model" "out-tok" "in+cache" "cost \$"
echo "-------------------------------------------------------------------------"

TOTAL="0"
OPUS_TOTAL="0"
while IFS=$'\t' read -r model in out cr cw; do
  [ -n "$model" ] || continue
  read -r ri ro rcr rcw <<< "$(rate "$model")"
  # cost = (in*ri + out*ro + cr*rcr + cw*rcw) / 1e6
  cost="$(awk -v i="$in" -v o="$out" -v c="$cr" -v w="$cw" \
           -v ri="$ri" -v ro="$ro" -v rcr="$rcr" -v rcw="$rcw" \
           'BEGIN{printf "%.2f", (i*ri + o*ro + c*rcr + w*rcw)/1000000}')"
  incache="$((in + cr + cw))"
  short="$(echo "$model" | sed 's/.*claude-//; s/-v1.*//; s/-2025.*//')"
  printf "%-40s %10s %10s %8s\n" "$short" "$out" "$incache" "$cost"
  TOTAL="$(awk -v t="$TOTAL" -v c="$cost" 'BEGIN{printf "%.2f", t+c}')"
  # Bucket by Opus FAMILY (any *opus* model), not just opus-4-8
  case "$model" in *opus*) OPUS_TOTAL="$(awk -v a="$OPUS_TOTAL" -v c="$cost" 'BEGIN{printf "%.2f", a+c}')" ;; esac
done <<< "$SUMMARY"

echo "-------------------------------------------------------------------------"
PCT="$(awk -v a="$OPUS_TOTAL" -v t="$TOTAL" 'BEGIN{ if(t>0) printf "%.0f", (a/t)*100; else print 0 }')"
printf "TOTAL: \$%s   |   Opus (family): \$%s (%s%%)\n" "$TOTAL" "$OPUS_TOTAL" "$PCT"
echo ""
echo "Opus family share is the delegation metric — lower over time = the main loop"
echo "is handing heavy work to cheaper agents instead of doing it itself."
# /retro should only flag Opus-% on 'operate' sessions; build/design sessions are
# legitimately Opus-heavy and should not trigger delegation warnings.

if [ -n "$SUBAGENT_NOTE" ]; then
  echo ""
  echo "$SUBAGENT_NOTE"
fi

# Optional: append a dated line to the cost ledger for trend tracking
if [ -n "$APPEND_LABEL" ]; then
  [ -z "$NOW" ] && NOW="$(date +%Y-%m-%d 2>/dev/null || echo undated)"
  mkdir -p "$(dirname "$COST_LEDGER")"
  if [ ! -f "$COST_LEDGER" ]; then
    {
      echo "# Syndicate Cost Ledger"
      echo ""
      echo "> Per-session cost, computed from transcripts by cost-report.sh (via /retro)."
      echo "> Watch the Opus % — it should trend DOWN as delegation discipline improves."
      echo ""
      echo "| Date | Session | Kind | Total \$ | Opus \$ | Opus % |"
      echo "|------|---------|------|---------|--------|--------|"
    } > "$COST_LEDGER"
  fi
  KIND_FIELD="${KIND:-untagged}"
  echo "| ${NOW} | ${APPEND_LABEL} | ${KIND_FIELD} | \$${TOTAL} | \$${OPUS_TOTAL} | ${PCT}% |" >> "$COST_LEDGER"
  echo ""
  echo "logged -> ${COST_LEDGER}"
fi
