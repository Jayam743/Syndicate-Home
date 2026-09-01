#!/usr/bin/env bash
# SessionEnd hook — audits each subagent's model against its intended model.
#
# Install: registered under hooks.SessionEnd by `syndicate-activate` — into the repo's
# .claude/settings.local.json in LAYERED mode (never BJ's global settings.json), or into
# ~/.claude/settings.json in STANDALONE mode. Do NOT hand-add it to BJ's shared file.
#
# What it does:
# 1. Reads the session transcript_path from the SessionEnd stdin JSON.
# 2. For every subagent spawned this session (<transcript>/subagents/agent-*.meta.json):
#    - resolves its agentType -> agents/<name>.md frontmatter (intended + fallback model)
#    - reads the model actually used from the co-named agent-<id>.jsonl
#    - normalizes both and compares: ok | fallback | DRIFT
# 3. Appends one row per auditable subagent to ~/.syndicate/ledger/model-audit.md.
#
# Built-in agents (Explore, general-purpose, etc.) have no repo frontmatter and are
# skipped — not auditable. Dedup is keyed on (session-id + agent-id), so re-running
# over the same session never double-writes.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

# --- read SessionEnd payload from stdin ---
PAYLOAD="$(cat 2>/dev/null || true)"
TRANSCRIPT="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "$TRANSCRIPT" ] || exit 0

SUB_DIR="${TRANSCRIPT%.jsonl}/subagents"
[ -d "$SUB_DIR" ] || exit 0

# --- resolve this repo's agents/ dir (installs may symlink the hook) ---
HOOK_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "$HOOK_PATH")/.." && pwd)"
AGENTS_DIR="${REPO_DIR}/agents"
[ -d "$AGENTS_DIR" ] || exit 0

AUDIT_FILE="${HOME}/.syndicate/ledger/model-audit.md"
TODAY="$(date +%Y-%m-%d)"
SESSION_ID="$(basename "$TRANSCRIPT" .jsonl)"
SESSION_SHORT="${SESSION_ID:0:8}"

# ledger/ already exists (created by install / session-end-ledger); guard anyway.
mkdir -p "$(dirname "$AUDIT_FILE")"
if [ ! -f "$AUDIT_FILE" ]; then
    {
        echo "# Syndicate Model Audit"
        echo ""
        echo "> One row per subagent spawn. Status DRIFT = the model that ran was neither"
        echo "> the agent's intended model nor its declared fallback. Written by"
        echo "> hooks/session-end-model-audit.sh on SessionEnd."
        echo ""
        echo "| Date | Session | Agent | Intended | Used | Status |"
        echo "|------|---------|-------|----------|------|--------|"
    } > "$AUDIT_FILE"
fi

# strip us.anthropic.claude- prefix and -vN / -YYYYMMDD suffixes (cost-report.sh style)
norm() { echo "$1" | sed 's/.*claude-//; s/-v[0-9].*//; s/-20[0-9][0-9].*//'; }

for meta in "$SUB_DIR"/agent-*.meta.json; do
    [ -e "$meta" ] || continue

    agent_id="$(basename "$meta" .meta.json)"   # agent-<id>
    agent_type="$(jq -r '.agentType // empty' "$meta" 2>/dev/null)"
    [ -n "$agent_type" ] || continue

    agent_name="$(printf '%s' "$agent_type" | tr '[:upper:]' '[:lower:]')"

    # dedup by (session-id + agent-id)
    dedup_key="${SESSION_ID}:${agent_id}"
    if grep -q "$dedup_key" "$AUDIT_FILE" 2>/dev/null; then
        continue
    fi

    # resolve agent frontmatter; built-ins have no file -> skip (not auditable)
    agent_md="$(readlink -f "${AGENTS_DIR}/${agent_name}.md" 2>/dev/null || true)"
    if [ -z "$agent_md" ] || [ ! -f "$agent_md" ]; then continue; fi

    intended_raw="$(grep -m1 '^model:' "$agent_md" | sed 's/^model:[[:space:]]*//; s/[[:space:]]*$//')"
    fallback_raw="$(grep -m1 '^fallback_model:' "$agent_md" | sed 's/^fallback_model:[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$intended_raw" ] || continue

    jsonl="${meta%.meta.json}.jsonl"
    used_raw=""
    if [ -f "$jsonl" ]; then
        used_raw="$(jq -r 'select(.type=="assistant") | .message.model' "$jsonl" 2>/dev/null \
                    | grep -v -e '^null$' -e '^$' -e '<synthetic>' | sort -u | head -1)"
    fi
    [ -n "$used_raw" ] || continue

    intended="$(norm "$intended_raw")"
    fallback="$(norm "$fallback_raw")"
    used="$(norm "$used_raw")"

    if [ "$used" = "$intended" ]; then
        status="ok"
    elif [ -n "$fallback" ] && [ "$used" = "$fallback" ]; then
        status="fallback"
    else
        status="DRIFT"
    fi

    printf '| %s | %s | %s | %s | %s | %s | <!-- %s -->\n' \
        "$TODAY" "$SESSION_SHORT" "$agent_name" "$intended" "$used" "$status" "$dedup_key" \
        >> "$AUDIT_FILE"
done
