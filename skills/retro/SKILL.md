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

This is a **read-only audit of the project** — do not edit project files, commit, or
push. (Three exceptions, all the skill's own bookkeeping / durable state, not changes to
the user's project: §1 appends a cost line via `cost-report.sh`, §6 may capture a new
operating rule to a memory file, and §7 appends findings via `loki-log.sh`.) Route per the
doctrine: Ledger owns accounting, Odin owns routing facts, Loki owns critique.

Be HONEST about uncertainty. If a number or model is not available to you, say
"not reported" — never guess. Label inferred values as (inferred) with the basis.

### 1. Token usage + cost (Ledger)
- **Run the cost report** — the transcript records usage + model per message, so we
  compute cost ourselves (and get a per-MODEL breakdown `/cost` can't):
  ```
  ~/.syndicate/scripts/cost-report.sh --per-subagent --append "<short session label>" --date <YYYY-MM-DD>
  ```
  This ALWAYS prints, and you MUST show the user, ALL of:
  - the **per-model table** (out-tok / in+cache / cost);
  - the **ON-DEMAND LIST** total (honest upper bound) AND the **EST. ACTUAL** total
    (list × `BEDROCK_COST_FACTOR`, the committed-use discount — this is the number that
    approximates the real AWS bill);
  - the **Opus-family % — the delegation metric** (a RATIO, unaffected by the factor);
  - the **per-subagent table** (from `--per-subagent`): agent · model · out-tok ·
    in+cache · tools · est-cost.
  It appends the est-actual line to `~/.syndicate/ledger/costs.md` for trend tracking.
- **Interpret the Opus-family %:** high (>70%) means the main loop did heavy work itself
  instead of delegating — flag it as a Cost Directive finding in §4. Low means
  delegation discipline is holding.
- `/cost` (client-side) is the harness's own tally if the user wants to cross-check;
  the model can't see its output, so cost-report.sh is the model-visible source.
- **The per-subagent table is REQUIRED** and comes from `--per-subagent` (above), which
  reads the subagent transcripts DIRECTLY — authoritative, not from memory. Always render
  it. Watch the `model` column: a mechanical agent (hermes/cipher/herald) or a formula
  agent (gauntlet/ledger) showing `opus-4-8` instead of its tier is cost **tier-drift**
  (the pins aren't effective / no per-spawn override) → flag in §4.

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
  - Did recall (Step 1.5) fire when it should have — and if skipped, was the skip
    STATED (user-supplied context is a valid, but must-be-disclosed, skip reason)?
  - For git-history work: was `git fetch` run before reconstructing merge state?
  - **Cost Directive: was the Opus-4.8 % high (>70%)?** If so, the main loop did
    heavy work (investigations, builds, reviews) inline on the top tier instead of
    spawning Specter/Forge/Athena or their workflows. Cite the specific tasks that
    should have been delegated. This is usually the highest-$ finding of the session.
- For each: what happened, what the doctrine says, severity.

### 5. Recommendations (Loki)
- Concrete, ranked improvements. Name the file/doctrine section and the exact change.

### 6. Rules in force — snapshot + persist the operating rules

The user establishes operating rules mid-session ("run wiring decisions through
Loki→Athena → future-harm"; "Muse/design-first for fuzzy ideas"; Loki-first choice
ordering; "don't install this cycle"; etc.). These MUST persist so a fresh session
already knows them without re-teaching. Do BOTH:

1. **Snapshot** the rules currently in force and show them in the report (one line each:
   the rule + where it's recorded). Sources:
   - the user's memory rules — read `MEMORY.md` and the `feedback`/`project` memory files
     (e.g. `[[decision-review-protocol]]`);
   - the doctrine decision-triggers + Loki-first ordering (`config/doctrine.md`);
   - the Godspeed state (`~/.syndicate/.godspeed`) and the absolute gates (prod/secrets/precheck).
2. **Capture any NEW rule** the user stated THIS session that is not yet a memory: write it
   as a `feedback`-type memory (name / description / **Why** / **How to apply**) and add its
   `MEMORY.md` index line — the SAME way the decision-review rule was captured. This memory
   write is the persistence mechanism (not a project edit), so it is allowed here. If every
   stated rule is already recorded, say "no new rules to capture."

### 7. Auto-log to Loki (ALWAYS — not optional)
After presenting the report, log EVERY finding from section 4/5 to Loki's improvement
log. This is automatic — do NOT ask "should I log this?". Loki is a self-sharpening
engine; it only sharpens if findings are recorded. For each finding run:

```
~/.syndicate/scripts/loki-log.sh --month <YYYY-MM> --status <applied|open|carried|wontfix> \
  --severity <low|medium|high> \
  --finding "<one-line finding>" \
  --doctrine "<what the doctrine says / 'no rule existed'>" \
  --action "<what was done this session, or 'none yet' if open>" \
  --session "<short session label>"
```

Status rules:
- `applied` — you fixed it during this session/retro (most retro findings)
- `open` — real, not yet fixed → becomes month-end review fodder
- `carried` — known issue you don't own (e.g. BJ's hook) → note, don't fix
- `wontfix` — considered and declined, with reason in --action

Writes to `~/.syndicate/loki/YYYY-MM.md` (stable path — works from any project).
After logging, tell the user: "Logged N findings to Loki (~/.syndicate/loki/). Run
/loki-review at month-end." Then STOP (still read-only — logging its own findings is
the one write /retro makes).

### Known carried issues (don't re-litigate, just note if unchanged)
- **stop-action-bias-detector false positives**: BJ's Stop hook gates on prose
  keywords (prod/deploy/etc.) in summaries, not just actions. This is BJ's hook, not
  Syndicate's — we can't fix it here; note it if it recurred, don't propose edits to it.

## A note on doing it in-loop vs spawning agents

For a SAME-SESSION audit, the main loop is the only actor that can see the full
transcript. Spawning Ledger/Loki/Odin as subagents would start them blind, cost tokens
to re-feed them the session, and add new "crew activity" that contaminates the very
thing being audited. So write each section in its crew member's lane, in-loop — do NOT
spawn subagents for a same-session retrospective. (This is itself a doctrine rule; see
the `retrospective` classification.)

## Output

The report is text only. The permitted writes are: §1's cost-ledger append, §6's
optional new-rule memory capture, and §7's required `loki-log.sh` findings append (to
`~/.syndicate/loki/YYYY-MM.md`). Do not write anything else (no project edits, no repo
commits) unless the user asks.
