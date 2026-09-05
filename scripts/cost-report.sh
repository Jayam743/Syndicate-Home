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
# Rates are per MILLION tokens — AWS Bedrock ON-DEMAND LIST price. Console-read 2026-09-01
# (operator, AWS console) — the per-model grid lives in rate() below. No >200K/long-context
# tier was OBSERVED in the console table: one flat rate per model regardless of context
# window, so the old [1m] 1.25x premium was removed as a phantom over-count.
# RE-VERIFY per-model on model-add: if any session exceeds 200K tokens, confirm no
# long-context tier applies — Anthropic's FIRST-PARTY API DOES tier >200K for 1M-context
# models, and Bedrock is NOT confirmed to mirror that. A console screenshot can miss such
# a row, and [1m] profiles exist precisely to run >200K sessions.
#
# TWO-LAYER cost model — keep these layers distinct:
#   1. on-demand LIST price (this table)  — the honest UPPER BOUND.
#   2. committed-use / EDP DISCOUNT       — a SEPARATE layer, captured by
#      BEDROCK_COST_FACTOR (default 0.42, calibrated from real AWS bills + /usage —
#      see the COST_FACTOR block below). Do NOT bake this discount into the rate table;
#      that would double-correct against the calibrated factor.
# The report prints BOTH the on-demand list and the est. actual (list x factor). The
# Opus-% delegation metric is a RATIO, so the factor never affects it.
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
PER_SUBAGENT=""

# Effective-cost factor: ACTUAL Bedrock bill as a fraction of on-demand LIST — a
# committed-use/EDP discount. It is NOT perfectly flat: sessions with different
# output/cache mixes discount slightly differently, so EST. ACTUAL is an APPROXIMATION
# (treat as ±~10%), NEVER a precise bill. Calibrated from ground-truth actuals
# (AWS Cost Explorer + operator /usage datapoints):
#   2026-08-27   $28.58  / $54.10  = 0.528   ([1m] session, premium removed)
#   2026-08-31   $50.55  / $107.93 = 0.468
#   2026-08-31   $191    / $454.16 = 0.420   (astrolabe, /usage)
#   cotterpin    $180.09 / $424.68 = 0.424   (retro, operator-supplied)
#   2026-09-02   $203    / $485.40 = 0.418   (salvo cutover, /usage)
#   2026-09-03   $124    / $304.22 = 0.408   (salvo finish, /usage)
#   token-weighted across all six = 777.22 / 1830.49 = 0.425  -> default 0.42
# The four new /usage datapoints dominate by list volume (1668 of 1830) and land at
# 0.418; the two small early Cost-Explorer pairs pull the weighted mean to ~0.425,
# rounded to 0.42. The old 0.49 default consistently OVER-read est. actual ~16% vs
# real bills. Add more (actual/list) pairs over time and re-weight. Override per-run
# with env BEDROCK_COST_FACTOR; 1.0 = pure on-demand list. The Opus-% delegation
# metric is a RATIO, so this factor never affects it.
COST_FACTOR="${BEDROCK_COST_FACTOR:-0.42}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcript) TRANSCRIPT="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --append) APPEND_LABEL="$2"; shift 2 ;;
    --date) NOW="$2"; shift 2 ;;
    --kind) KIND="$2"; shift 2 ;;
    --per-subagent) PER_SUBAGENT=1; shift ;;
    *) shift ;;
  esac
done

# Resolve transcript: explicit > project slug > newest in cwd's project dir
if [ -z "$TRANSCRIPT" ]; then
  if [ -n "$PROJECT" ]; then
    dir="${PROJECTS}/${PROJECT}"
  else
    # slugify the way Claude Code does (/ -> -), but anchor on the git repo TOPLEVEL
    # rather than raw $pwd (issue #35): a cwd that has drifted into a subdir of the
    # repo would otherwise slugify to a non-existent project dir and mis-resolve. Fall
    # back to $pwd when not in a git repo.
    base="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    slug="$(printf '%s' "$base" | sed 's#/#-#g')"
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
# Console-read 2026-09-01 (operator, AWS console) against the Bedrock pricing table:
#   opus (5/4.8/4.7): 5 | 25 | 0.50 | 6.25   (console-read)
#   sonnet 5:         2 | 10 | 0.20 | 2.50   (console-read)
#   haiku 4.5:        1 |  5 | 0.10 | 1.25   (INFERRED, not console-exact — haiku is NOT
#                                             in the console table; rate follows the
#                                             0.1x-input cache-read pattern)
# No >200K/long-context tier was OBSERVED in the console table: one flat rate per model
# regardless of context window, so [1m] ids get the SAME base rate — the previous 1.25x
# [1m] premium was a phantom over-count and has been removed. RE-VERIFY on model-add: if a
# session exceeds 200K tokens, confirm no long-context tier applies (Anthropic first-party
# DOES tier >200K; Bedrock mirror unconfirmed).
rate() { # $1=model-id  -> echoes "in out cread cwrite"
  case "$1" in
    *opus*)         echo "5 25 0.5 6.25" ;;
    *sonnet*)       echo "2 10 0.2 2.5" ;;   # Sonnet 5 — console-read 2026-09-01: no >200K tier observed (re-verify if >200K sessions; Bedrock mirror of first-party >200K tiers unconfirmed)
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
# Estimated actual = on-demand LIST x effective factor (see COST_FACTOR above).
ACT_TOTAL="$(awk -v t="$TOTAL" -v f="$COST_FACTOR" 'BEGIN{printf "%.2f", t*f}')"
ACT_OPUS="$(awk -v a="$OPUS_TOTAL" -v f="$COST_FACTOR" 'BEGIN{printf "%.2f", a*f}')"
printf "ON-DEMAND LIST: \$%s   |   Opus (family): \$%s (%s%%)\n" "$TOTAL" "$OPUS_TOTAL" "$PCT"
printf "EST. ACTUAL (~x%s, ±~10%%): \$%s   |   Opus (family): \$%s   [override: BEDROCK_COST_FACTOR]\n" "$COST_FACTOR" "$ACT_TOTAL" "$ACT_OPUS"
echo ""
echo "ON-DEMAND LIST is the honest upper bound. EST. ACTUAL applies a committed-use"
echo "discount factor (~${COST_FACTOR}x) calibrated from AWS Cost Explorer actuals — it is an"
echo "APPROXIMATION (±~10%, small sample), NOT a precise bill; don't over-trust the digits."
echo "Opus family share is the delegation metric (a RATIO — unaffected by the factor);"
echo "lower over time = the main loop is handing heavy work to cheaper agents."
# /retro should only flag Opus-% on 'operate' sessions; build/design sessions are
# legitimately Opus-heavy and should not trigger delegation warnings.

if [ -n "$SUBAGENT_NOTE" ]; then
  echo ""
  echo "$SUBAGENT_NOTE"
fi

# Optional per-subagent breakdown (--per-subagent): one row per subagent transcript
# — agent label (attributionAgent, else companion .meta.json agentType), model it
# ACTUALLY ran on (surfaces tier drift),
# tokens, tool_uses, and est. actual cost. Sorted by cost descending.
if [ -n "$PER_SUBAGENT" ] && [ "${#TRANSCRIPTS[@]}" -gt 1 ]; then
  echo ""
  echo "=== PER-SUBAGENT (est. actual, x${COST_FACTOR}) ==="
  printf "%-20s %-14s %10s %10s %6s %8s\n" "agent" "model" "out-tok" "in+cache" "tools" "cost \$"
  echo "-------------------------------------------------------------------------------"
  {
    for f in "${TRANSCRIPTS[@]:1}"; do
      [ -f "$f" ] || continue
      # Primary label: attributionAgent from the transcript. When that's absent
      # or the generic "general-purpose"/"unknown", fall back to the SECONDARY
      # source — agentType in the companion <transcript>.meta.json, which carries
      # the real persona slug (e.g. scribe/cipher/specter/herald). The jsonl
      # "slug" field is a random codename (e.g. "vivid-mapping-swing"), NOT the
      # persona, so it is deliberately unused. Only land on "general-purpose"
      # when neither source yields a real persona.
      lbl="$(jq -rs '[.[]|.attributionAgent]|map(select(.!=null and .!=""))|first // ""' "$f" 2>/dev/null)"
      case "$lbl" in
        ""|general-purpose|unknown)
          meta="${f%.jsonl}.meta.json"
          if [ -f "$meta" ]; then
            at="$(jq -r '.agentType // ""' "$meta" 2>/dev/null)"
            [ -n "$at" ] && lbl="$at"
          fi
          ;;
      esac
      [ -z "$lbl" ] && lbl="general-purpose"
      mdl="$(jq -rs '[.[]|select(.type=="assistant")|.message.model]|map(select(.!=null))|first // "?"' "$f" 2>/dev/null)"
      read -r si so scr scw <<< "$(jq -rs '
        [ .[]|select(.type=="assistant")|.message|select(.usage!=null)
          | {i:(.usage.input_tokens//0),o:(.usage.output_tokens//0),
             r:(.usage.cache_read_input_tokens//0),w:(.usage.cache_creation_input_tokens//0)} ]
        | "\([.[].i]|add // 0) \([.[].o]|add // 0) \([.[].r]|add // 0) \([.[].w]|add // 0)"' "$f" 2>/dev/null)"
      si=${si:-0}; so=${so:-0}; scr=${scr:-0}; scw=${scw:-0}
      tools="$(grep -c '"type":"tool_use"' "$f" 2>/dev/null || true)"; tools=${tools:-0}
      read -r ri ro rcr rcw <<< "$(rate "$mdl")"
      cost="$(awk -v i="$si" -v o="$so" -v c="$scr" -v w="$scw" -v ri="$ri" -v ro="$ro" -v rcr="$rcr" -v rcw="$rcw" -v f="$COST_FACTOR" \
              'BEGIN{printf "%.2f", ((i*ri + o*ro + c*rcr + w*rcw)/1000000)*f}')"
      incache=$((si + scr + scw))
      short="$(echo "$mdl" | sed 's/.*claude-//; s/-v1.*//; s/-2025.*//')"
      printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$cost" "$lbl" "$short" "$so" "$incache" "$tools"
    done
  } | sort -t"$(printf '\t')" -k1 -rn | while IFS="$(printf '\t')" read -r cost lbl short so incache tools; do
      printf "%-20s %-14s %10s %10s %6s %8s\n" "$lbl" "$short" "$so" "$incache" "$tools" "$cost"
    done
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
      echo "> \$ columns are EST. ACTUAL ≈ on-demand list x BEDROCK_COST_FACTOR (default 0.42,"
      echo "> committed-use discount) — an APPROXIMATION (±~10%), not a precise bill. Opus % is a"
      echo "> ratio (factor-independent). Rows before 2026-08-27 are raw on-demand list (unfactored)."
      echo ""
      echo "| Date | Session | Kind | Actual \$ | Opus \$ | Opus % |"
      echo "|------|---------|------|----------|--------|--------|"
    } > "$COST_LEDGER"
  fi
  KIND_FIELD="${KIND:-untagged}"
  echo "| ${NOW} | ${APPEND_LABEL} | ${KIND_FIELD} | \$${ACT_TOTAL} | \$${ACT_OPUS} | ${PCT}% |" >> "$COST_LEDGER"
  echo ""
  echo "logged -> ${COST_LEDGER}"
fi
