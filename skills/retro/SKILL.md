---
name: retro
description: "Session retrospective / self-audit — run at the END of a session. Reports token usage, models, which crew agents ran, mistakes/routing gaps, and improvements. Guards against auditing an empty session."
---

# /retro — Session Retrospective

Run this **LAST**, after all the real work in a session is done. It audits the session
it runs in — what the crew did, what it cost, and what went wrong — so you can improve
the workflow. Running it early just audits an empty session.

## ⏱ Timing (read this first)

**Run `/retro` at the END of a working session, not the start.** A retrospective needs
work to reflect on. If you run it right after `/engage` + `/syndicate`, there's nothing
to audit — you'll get an empty report.

## Empty-session guard (do this before writing the report)

First, assess whether there's anything worth auditing. Count the real activity this
session: subagents spawned, workflows run, files changed, commits, non-trivial routing
decisions. **If activity is near-zero** (only session setup — /engage, /syndicate, a
branch switch, a couple of reads):

> Stop and say: "Nothing substantial to audit yet — this session has only [list the
> setup actions]. Run `/retro` again after you've done the work you want reviewed."

Do NOT produce a full five-section report for an empty session. Say what little
happened and stop.

## The report (only if there's real activity)

This is a **read-only audit** — do not edit files, commit, or push. Route per the
doctrine: Ledger owns accounting, Odin owns routing facts, Loki owns critique.

Be HONEST about uncertainty. If a number or model is not available to you, say
"not reported" — never guess. Label inferred values as (inferred) with the basis.

### 1. Token usage (Ledger)
- **The model cannot see its own token meter.** Do NOT type a total you "estimate" —
  that's fabrication. The honest answer for session total is: "run `/cost`" (harness-
  sourced) or read the SessionEnd ledger hook output.
- Per-subagent breakdown: a table of every subagent spawned — label/task, tokens,
  tool-uses, duration — using ONLY the completion/usage numbers actually reported to
  you in-session. Mark still-running ones "pending".

### 2. Models used (Ledger + Odin)
- Main session model (from the environment block — this is known, not inferred).
- Per-agent model: if not explicitly reported, say so, and give the inheritance
  default as (inferred: agents inherit the session model unless a `model:` override).

### 3. Syndicate crew usage (Odin)
- Of the 14 — odin, muse, scribe, forge, athena, gauntlet, specter, hermes, titan,
  safecracker, ledger, herald, loki, cipher — which ACTUALLY ran.
- Separately: built-in agents used (Explore, Plan, general-purpose).
- State plainly if zero crew agents ran.

### 4. Mistakes & routing gaps (Loki)
- Every doctrine violation / routing miss. Check specifically:
  - Was Scribe's recraft (Step 0.5) applied to substantial requests, or skipped?
  - Did any request match NO classification and get freelanced?
  - Was an agent used that shouldn't have been, or one skipped that should have run?
  - Did recall (Step 1.5) fire when it should have?
- For each: what happened, what the doctrine says, severity.

### 5. Recommendations (Loki)
- Concrete, ranked improvements. Name the file/doctrine section and the exact change.
- Optionally, offer to write the highest-value ones to Loki's log
  (`loki/logs/YYYY-MM.md`) — but only if the user says so.

## A note on doing it in-loop vs spawning agents

For a SAME-SESSION audit, the main loop is the only actor that can see the full
transcript. Spawning Ledger/Loki/Odin as subagents would start them blind, cost tokens
to re-feed them the session, and add new "crew activity" that contaminates the very
thing being audited. So write each section in its crew member's lane, in-loop — do NOT
spawn subagents for a same-session retrospective. (This is itself a doctrine rule; see
the `retrospective` classification.)

## Output

Text only. Do not write to any file unless the user asks afterward.
