# Evidence Packets

> "Troubleshooting starts with facts, not folklore."

After every pipeline completes, the system produces an Evidence Packet — a structured
record of what happened, who did what, and what the outcome was. This is how Ledger
tracks work and Loki identifies improvement opportunities.

## What Goes in an Evidence Packet

```
Pipeline ID: [timestamp-based, e.g. 2026-07-29T10:34:00]
Triggered by: [user's original prompt]
Pipeline: [e.g. Scribe → Specter → Loki → Forge → Athena → Hermes]

Stages:
  1. Scribe
     - Input: "fix the headscale coppermind path"
     - Additions: "repo path, read-only first, container ID"
     - Output: [refined prompt, truncated]
     - Duration: ~5s
     - model_intended: us.anthropic.claude-opus-4-8
     - model_used: us.anthropic.claude-opus-4-8

  2. Specter
     - Hypotheses tested: 3
     - Root cause: COPPERMIND_PATH unset in compose env
     - Options presented: A (recommended), B, C
     - User chose: A
     - model_intended: us.anthropic.claude-opus-4-8
     - model_used: us.anthropic.claude-opus-4-8

  3. Forge
     - Files modified: services/rumrunner/compose.yml
     - Lines changed: +2
     - Lint: passed
     - model_intended: us.anthropic.claude-opus-4-8
     - model_used: us.anthropic.claude-opus-4-8

  4. Athena
     - Findings: 0 (clean)
     - model_intended: us.anthropic.claude-opus-4-7
     - model_used: us.anthropic.claude-opus-4-7

  5. Hermes
     - Branch: fix/483-headscale-coppermind-path-env
     - MR: !147
     - Target: release/2.0.1
     - model_intended: us.anthropic.claude-haiku-4-5-20251001-v1:0
     - model_used: us.anthropic.claude-haiku-4-5-20251001-v1:0

Outcome: MR opened, awaiting review
Duration: ~4 minutes total
Logged to: Ledger (current-week.md)
```

## Where Evidence Packets Live

- **Short-term**: `~/.syndicate/evidence/YYYY-MM-DD/` (one file per pipeline)
- **Summarized**: in Ledger's current-week.md (one bullet per pipeline)
- **Monthly**: rolled up into Loki's monthly review

## Who Uses Them

| Consumer | Uses for |
|----------|----------|
| **Ledger** | Building weekly status reports |
| **Loki** | Finding patterns (slow stages, repeated failures, routing misses) |
| **User** | "What did that pipeline actually do?" — audit trail |
| **Specter** | Reference for similar past investigations |

## What Makes a Good Evidence Packet

- **Complete** — every stage that ran, including skipped ones
- **Honest** — if something failed or was retried, say so
- **Concise** — one line per stage is enough, not full transcripts
- **Traceable** — includes branch name, MR number, file paths
- **Model-auditable** — `model_intended` (from agent frontmatter) and `model_used`
  (actual resolved model, emitted per-subagent in the transcript JSONL as `.model`)

Loki's monthly review asserts model_used == model_intended per spawn to detect any
silent fallthrough (e.g., Haiku resolving to Opus due to pin misconfiguration).

## Borrowed Principle

From BJ's GitOps philosophy: *"An Evidence Packet captures what happened so
troubleshooting starts with facts, not folklore."*

In airport deployments, this proves a system was installed correctly.
In Syndicate, this proves your AI agents did what you asked — and shows you
exactly where things went sideways when they didn't.
