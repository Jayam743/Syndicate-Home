---
name: loki-review
description: "Month-end Loki review — read the month's logged findings, sort done-vs-open, spot repeat patterns, propose improvements, brainstorm, then sync to the repo."
---

# /loki-review — Monthly Self-Improvement Cycle

This is Loki's active loop. Over the month, `/retro` auto-logs findings to
`~/.syndicate/loki/YYYY-MM.md`. At month-end (or whenever you want to take stock),
`/loki-review` reads them all, tells you what's done vs still open, spots patterns
across sessions, proposes new improvements, and brainstorms with you.

## Trigger

- `/loki-review` — review the current month
- `/loki-review 2026-07` — review a specific month

## Procedure

### 1. Load the month's findings
Read `~/.syndicate/loki/<MONTH>.md` (default: current month). If it doesn't exist or
is empty, say "No findings logged for <MONTH> — run some sessions with /retro first"
and stop.

### 2. Sort by status
Group the findings:
- **Applied** — already fixed. Confirm each is still in place (spot-check the doctrine/
  file it claims to have changed — did the fix survive, or get reverted?).
- **Open** — real findings never fixed. These are the main work list.
- **Carried** — known issues we don't own (e.g. BJ's hooks). Note if any recurred a
  lot this month — high recurrence is itself a signal worth escalating to the user.
- **Wontfix** — declined. Skip unless a wontfix keeps coming back (maybe reconsider).

### 3. Spot patterns (the real value)
Look ACROSS findings, not just at each one:
- Same finding logged in 3+ sessions? → it's systemic, not incidental. Rank it top.
- A cluster around one agent/step (e.g. "recall under-fires" twice)? → that step's
  design is off, not the execution.
- Applied fixes that DIDN'T stop the problem recurring? → the fix was wrong; rethink.

### 4. Propose & brainstorm
Present a ranked improvement plan:
```
═══ LOKI MONTHLY REVIEW — <MONTH> ═══
Logged: N findings (X applied, Y open, Z carried)

Already fixed this month:
  • [applied finding] — verified still in place / REGRESSED

Still open (work list, ranked):
  1. [finding] — proposed fix: [file + exact change]
  2. ...

Patterns spotted:
  • [finding X appeared in 3 sessions → systemic]

Recommended for next month:
  • [new improvement idea]

What do you want to tackle? (or "just log it and move on")
```
Then BRAINSTORM with the user — this is a conversation, not a report dump. Loki
proposes; the human decides what actually gets built (Axiom: human holds the gate).

### 5. Sync to the repo (version the history)
After the review, copy the month's log into the Syndicate repo so it's
version-controlled:
```
cp ~/.syndicate/loki/<MONTH>.md <syndicate-repo>/loki/logs/<MONTH>.md
```
Then offer to commit it ("commit this month's Loki log?"). The live copy at
`~/.syndicate/loki/` stays as the working log; `loki/logs/` in the repo is the
durable, committed history.

### 6. Apply what the user approves
For each improvement the user greenlights, make the change (route through the normal
doctrine — code-change → pipeline, etc.), then update that finding's status to
`applied` in the log (or add a new applied entry noting the month-review action).
An `applied` finding MUST carry a `- **Pinned-by:** <ref>` line (the commit/PR/MR
that pins the fix) — `loki-log.sh --status applied` now requires `--pinned-by`.

### 7. Regenerate the defect CHANGELOG
After the status-flips in step 6, rebuild the resolved-defect rollup:
```
scripts/loki-changelog.sh
```
It sources `loki/logs/*.md` (ALL months), selects every `[applied]` finding that
carries a `Pinned-by` ref, and rewrites `loki/CHANGELOG.md` from scratch — one row
per defect: **defect** (title), **fix** (action taken), **pinned-by** (ref), **when**.

- **Review the backfill dry-run.** The script prints every `[applied]` finding that
  LACKS a `Pinned-by` line as "needs triage". For each: either backfill the pinning
  ref (if the fix really shipped) or reclassify the finding (e.g. back to `open` if
  the action was "none yet"). They stay OUT of the CHANGELOG until pinned — never
  silently promote or drop them.
- **It is REGENERABLE, not append-only.** `applied` is rebuttable and can regress; a
  full regenerate means a finding that loses its `Pinned-by` (or flips status) drops
  out automatically. Do not hand-edit `loki/CHANGELOG.md`.
- Offer to commit `CHANGELOG.md` together with the synced log from step 5.

> Recall integration is DEFERRED: when it lands, recall will index `CHANGELOG.md`
> (small, resolved-only), NOT the raw log.

## Rules
- **Never auto-apply.** Loki proposes; the human approves each change (Axiom 11-adjacent:
  Loki never self-applies improvements to the system).
- **Verify applied fixes.** "Applied" in the log is a claim — spot-check it's real and
  didn't regress. An applied-but-regressed finding is worse than an open one.
- **Patterns over incidents.** One-off findings are noise; repeated ones are the signal.
- This runs in-loop (like /retro) — don't spawn subagents to read a local log file.

## Why this exists
Without it, Loki is a notebook nobody rereads. `/retro` fills the notebook every
session; `/loki-review` is the standing meeting where the notebook becomes actual
change. That closes the self-sharpening loop: observe (retro) → record (loki-log) →
review (loki-review) → improve → observe again.
