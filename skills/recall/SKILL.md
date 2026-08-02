---
name: recall
description: "Pull prior context — the 2-3 most relevant recent sessions + repo merge history — before troubleshooting or building."
---

# /recall — Context Recall

Before diving into "why is this crashing?" or "how do we make this better?", pull
what you already know. Recall finds the most relevant recent conversations about the
topic AND the repo's recent merge history, so you start warm, not cold.

## Trigger

- `/recall "the topic or error"` — get a context brief
- Automatic: the dispatch doctrine runs recall for investigate/goal-seek/code-change/review

## What It Does

```
scripts/recall.sh --repo <repo> "your question"
```

1. **Searches your existing session transcripts** (`~/.claude/projects/*/*.jsonl`)
   for keywords from your request — matched against session titles and message text
2. **Ranks by relevance, then recency** — takes the top 2-3 (never a deep dump)
3. **Adds repo merge history** — recent merged MRs/PRs (glab/gh), or local
   `git log --merges` as an offline fallback
4. **Emits a context brief** the agent folds into its prompt as PRIOR CONTEXT

## Design Intent

The user's rule: *"pull up the recent 2-3 histories about this specific thing plus
the project's merge history — but don't go back a lot."* Recall is capped at 2-3
sessions on purpose. Enough to know what you already tried; not so much it drowns
the prompt or drags in stale threads.

## Nothing Is Moved

Recall is READ-ONLY. Your 58 existing transcripts stay exactly where Claude Code
put them. Recall just indexes them in place at query time. This IS the "history
transfer" — your past work becomes searchable without migration or risk.

## Examples

```
/recall "nightly job hanging"
  → finds your 2 recent sessions about the nightly job
  → + last 10 merges (maybe the change that broke it is right there)

/recall "auth timeout"
  → finds the debugging session from last week
  → you don't re-explain what you already ruled out
```

## Options

```
scripts/recall.sh --max 3 --repo /path/to/repo --mrs 10 "query"
```
- `--max N` — how many past sessions (default 3)
- `--repo DIR` — which repo's merge history (default: cwd)
- `--mrs N` — how many merges to list (default 10)

## When NOT to Use

- Brand-new topic with no history → nothing to recall, just proceed
- Single-purpose tasks (commit, convert a doc) → no context needed
- Conception (Muse) → starts fresh by design
