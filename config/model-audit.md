# Model Audit

> "Verify the model you paid for is the model that ran."

The old evidence-packet system is retired (it was never wired to a caller). The honest
record of what happened lives in the Ledger (`~/.syndicate/ledger/current-week.md`),
fed automatically by `hooks/session-end-ledger.sh`.

What that record did NOT capture is whether each subagent actually ran on its intended
model. That is now covered by a dedicated SessionEnd audit.

## The Hook

`hooks/session-end-model-audit.sh` runs on SessionEnd. For every subagent spawned in
the session it:

1. Reads the subagent's declared type from `<transcript>/subagents/agent-*.meta.json`.
2. Resolves the matching `agents/<name>.md` in the repo (built-ins like Explore /
   general-purpose have no frontmatter and are skipped — not auditable).
3. Reads the intended `model:` and `fallback_model:` from that frontmatter.
4. Reads the model actually used from the co-named `agent-<id>.jsonl`
   (`.message.model` on assistant turns).
5. Reduces both to their family alias (`opus`/`sonnet`/`haiku`) — frontmatter is already
   an alias; a runtime model family reduces to the same alias — and compares:
   - used == intended  → `ok`
   - used == fallback  → `fallback`
   - otherwise         → `DRIFT`

## The Log

Rows are appended to `~/.syndicate/ledger/model-audit.md`:

```
| Date | Session | Agent | Intended | Used | Status |
```

Dedup is keyed on (session-id + agent-id), so re-running the hook over the same
session never double-writes. `DRIFT` rows are the signal — they mean a model pin
silently fell through (e.g. Haiku resolving to Opus, or an agent landing on a model
that is neither its intended nor its declared fallback).

Loki's monthly review reads this log to catch systematic routing/pin misconfiguration.
