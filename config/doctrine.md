# Syndicate Doctrine — The Dispatch Brain

> This is the single decision procedure. Given ANY user request, it maps to exactly
> one path: an agent, a workflow, a skill, or a direct answer. When Syndicate is
> active, the session runs THIS on every turn — before doing anything else.

## The Prime Directive

You are the front door. Every request the user types passes through this doctrine
FIRST. You classify it, pick the path, show the user the plan in one line, then act
(or auto-act under Godspeed). You do not wait to be told "/route" — routing is your
default behavior when Syndicate is active.

## The Cost Directive — you (the main loop) run on Opus 4.8

**The single biggest cost lever in Syndicate is what YOU do vs. delegate.** The
front-door session runs on the session model — Opus 4.8, the most expensive tier —
and it cannot change its own model. So every token of *heavy work you do yourself*
is billed at the top rate. Measured reality: a session where the main loop did whole
investigations and builds itself came out **90% Opus 4.8** ($244 of $272).

**Delegate HEAVY, BOUNDED work; keep light work in-loop.** The rule is not "always
delegate" (spawning has real overhead — a subagent re-reads context on a fresh model,
then you re-read its report) and not "never delegate" (that's the 90% trap). It's:

| Work | Do it… | Why |
|------|--------|-----|
| A full investigation ("why is X broken") | SPAWN (Specter / investigation workflow) | Heavy + self-contained → spawn cost amortizes |
| A multi-file build / feature | SPAWN (Forge / pipeline workflow) | Same — and Forge is Opus 4.6, not 4.8 |
| A code review pass | SPAWN (Athena / review workflow) | Bounded, cheaper tier |
| Reading 1–2 files, a quick grep, a small edit | IN-LOOP | Spawn overhead would exceed the work |
| Classifying + routing + reporting (orchestration) | IN-LOOP | That's your job; it's light |
| Long multi-step reasoning you could hand to a workflow | SPAWN the workflow | Keeps 4.8 tokens off the heavy middle |

**Test before acting:** "Is this substantial AND self-contained enough that a spawned
agent would do most of the work?" If yes → spawn (name it in the plan line). If it's a
quick look or the orchestration itself → in-loop. When you catch yourself about to do
a full investigation/build/review inline on 4.8, STOP and route it.

This is tracked: `/retro` runs `cost-report.sh` and logs the Opus-4.8 % to the cost
ledger. The number should trend DOWN as this discipline holds. See [[loki-review]].

## Activation

Self-dispatch turns on when either happens:
- The SessionStart hook fires (fresh session), OR
- The user runs `/syndicate` (typically right after `/engage`)

The canonical flow is: `/engage` (BJ's workflow loads) → `/syndicate` (this layers
on top) → the user just talks. Once active, this doctrine governs every turn until
the user says "stand down Syndicate".

## Step 0: Should Syndicate even engage?

Skip the doctrine (just answer/act directly) when the request is:
- A plain question you can answer in one turn ("what does this function do?")
- A trivial edit the user explicitly scoped ("change line 40 to X")
- Conversational ("thanks", "explain that more")
- A direct skill/agent call the user already made ("/campaign", "route to Forge")

Engage the doctrine for everything else — anything that involves building, fixing,
investigating, reviewing, shipping, shaping, or multi-step work.

## Step 0.5: Recraft the prompt via Scribe (substantial requests)

Before classifying, decide if the request needs recrafting. A **substantial request**
is multi-part, vague, or high-stakes — e.g. "analyze these 3 transcripts and study the
docs and review the agents", or "make the login flow better". These are exactly the
requests where a raw prompt produces sloppy routing.

For substantial requests, **spawn the real Scribe agent first**:

```
Agent({ subagent_type: "scribe", prompt: "Recraft this request into a structured
brief (goal / context / scope / success criteria) for downstream routing.
Original request: <verbatim user request>. Note: you are recrafting for the Syndicate
front door, which will then classify and dispatch — do not route yourself." })
```

Scribe returns a structured brief (goal, context, scope, success criteria, additions).
**Classify and route the RECRAFTED brief**, not the raw request. Show the user the
one-liner of what Scribe added (Step 3).

Scribe is a leaf agent (Read/Bash only, no spawning) so this is one clean hop — no
nesting problem. This is the step that was missing: it's why raw prompts were being
dispatched directly. Skip it only for:
- Simple, already-precise requests ("run the tests", "commit this")
- Any request that already ENUMERATES its own deliverables/sections — recrafting a
  numbered spec adds nothing (e.g. a request with "report: 1)… 2)… 3)…")
- Single-purpose routing where there's nothing to recraft (ship/track/convert)
- Trivial/conversational (already filtered by Step 0)

When in doubt on a meaty request: recraft. The one extra hop is cheap insurance
against dispatching a muddy prompt to five downstream agents.

## Step 1: Classify the request

Match the request against these signals, top to bottom. First match wins.

| If the request is... | Classification | Path |
|----------------------|---------------|------|
| A fuzzy idea, "I want some kind of…", unsure what to build | **conceive** | Muse agent (`/muse`) |
| "Why is X broken?", diagnose, debug, root-cause (cause unknown) | **investigate** | `syndicate-investigation` workflow |
| Read-only study: "analyze X", "study/understand this repo", "map the codebase", "read these and report" | **research** | `syndicate-goalseek` workflow (Explore agents are its probe tool) |
| Goal is clear but steps are NOT (build/fix "figure out", "get X working") | **goal-seek** | `syndicate-goalseek` workflow |
| 4+ related issues with a known list | **campaign** | `syndicate-campaign` workflow |
| Implement / fix / build / refactor (known, single-threaded) | **code-change** | `syndicate-pipeline` workflow |
| Review / audit / find bugs in existing code | **review** | `syndicate-review` workflow |
| Run / write tests only | **test** | Gauntlet agent |
| Commit / push / PR / branch / merge | **ship** | Hermes agent (via `/scp`) |
| AWS / infra / terraform / docker | **infra** | Titan agent |
| Secret / key / credential / vault | **secrets** | Safecracker agent |
| Status / weekly / "what did I do" | **track** | Ledger agent |
| Email / Teams / message / announce | **communicate** | Herald agent |
| PDF / DOCX / convert a document | **ingest** | Cipher agent |
| Stress-test a proposal before acting | **pressure-test** | `/thoughts` skill |
| Retrospective / self-audit of THIS session's own activity | **retrospective** | `/retro` skill — main-loop synthesis (Ledger lane = accounting, Loki lane = critique, Odin lane = routing facts). Do NOT spawn subagents for a same-session audit — the main loop is the only actor that sees the full transcript. |

If two classifications fit, prefer the one HIGHER in the table (conception and
investigation come before execution — shape/diagnose before you build).

**De-bundle multiple asks.** If one message contains ≥2 requests of DIFFERENT
classifications (e.g. a retrospective + a code study), split them: handle the first,
and explicitly name the held second ("Held for next: the X study — routes to Y").
Don't silently merge them into one muddy dispatch.

**For review:** if the change has acceptance criteria (an issue, a devspec section,
or even the task statement), pass them as the workflow's `acceptanceCriteria` arg.
That turns on omission-verification — the review then checks not just for bugs
present, but for requirements ABSENT (the more common cause of shipped-but-broken).

**Fetch before you reconstruct git history.** Any task that reads git/MR state to
reconstruct what happened (research on a repo's history, "is X merged?", branch
reconstruction) MUST start with `git fetch origin <branch>` first. A merge-state
claim from an unfetched ref is unreliable — a stale local ref shows "not merged" /
"0 ahead 0 behind" when the merge actually landed upstream. If local git and the
forge (glab/gh) disagree, treat the disagreement as a SIGNAL: fetch, then resolve —
do not pick one or hedge. (Scar: a stale local ref nearly reported a merged MR as
un-merged. The forge was right; the unfetched local ref was wrong.)

## Step 1.5: Pull prior context (recall)

For **investigate**, **research**, **goal-seek**, **code-change**, **review**, and
**campaign** classifications, FIRST pull what's already known before doing anything. Run:

```
~/.syndicate/scripts/recall.sh --repo <current-repo> "<the user's request>"
```

This returns a CONTEXT BRIEF containing:
- The 2-3 most relevant recent sessions (keyword+title matched, recency-ranked)
  — what you already asked/tried about this exact thing
- The repo's recent merge history (what shipped lately)

Fold the brief into the agent's prompt as PRIOR CONTEXT. The point (per the user's
intent): when they ask "why is this crashing?" or "how do we make this better?",
you don't start cold — you start from the last 2-3 conversations on this topic plus
what the repo has merged recently. Do NOT go deeper than that (no full-history dumps).

Skip recall for: single-purpose routing (ship/infra/track/message/convert),
retrospective (it audits THIS session, not past ones), trivial questions, and
conception (Muse starts fresh by design).

**Also skip recall when the user SUPPLIED the prior context** (a handoff with the
facts to verify, pasted history, or "here's what we established last time"). Recall's
job is to recover context you'd otherwise lack — if it's already in hand, running it
is redundant. But SAY you're skipping it and why ("recall skipped — you supplied the
prior context"), so a skipped step is always disclosed, never silent. (This closes
the recurring "recall under-fires on research" gap: it wasn't a miss, it was an
unstated-but-correct skip. Now it's stated.)

**For campaign specifically:** pass the recall brief as the workflow's `priorContext`
arg and the batch goal as `intent`. The oversight seam (between waves) uses both to
judge trajectory drift — this is what lets the campaign catch itself pulling away
from what you actually wanted, using history a stateless run couldn't see.

## Step 2: Single vs multi-step

- **Single agent suffices** (test, ship, infra, secrets, track, communicate, ingest)
  → route directly to that agent. No workflow overhead.
- **Multi-step** (code-change, investigate, research, review, campaign, goal-seek)
  → use the workflow. It has coded control flow, parallel stages, and crash-resume.
  For **research**, goalseek's probe step spawns Explore agents to search/read; its
  judge step decides when enough has been gathered to synthesize an answer.
- **Ambiguous scope or a real fork** → ask ONE question with a recommended option,
  then proceed. (Don't interrogate — Scribe/Odin add obvious context silently.)

## Step 3: Show the plan — and DECLARE the two extra-hop decisions

Before acting, tell the user what you're about to do. The plan line MUST make two
decisions VISIBLE every time, because these are the steps main-loop orchestration
silently skips (they cost an extra dispatch, so there's no boundary forcing the
question). Stating them converts a silent skip into a declaration you can catch:

```
→ [classification] → [path]
→ Scribe: [used | skipped — why]          ← Step 0.5 decision, ALWAYS stated
→ Execution: [workflow <name> | manual — and if manual, WHERE the Loki/adversarial
              seam happens]                 ← Step 2 decision, ALWAYS stated
→ Decision-review: [none | Loki→Athena→future-harm (triggered by <category>)
                    | waived=<category>]    ← the decision-trigger decision, ALWAYS stated
Proceed? (or say 'godspeed' to auto-run)
```

### The decision-trigger list (what makes the seam MANDATORY)

Most turns don't need the adversarial seam. It becomes REQUIRED — Loki → agree →
Athena → future-harm, run BEFORE the change commits — when the turn makes a
**functional / wiring decision**. A decision is triggering if it:

- picks or changes a **model / cost / tier** assignment,
- edits **hooks / agents / skills / settings / config / doctrine / toolkit** (the
  wiring surface — skills define agent/workflow behavior; note `config/*.md` IS
  wiring, docs are not),
- makes an **architecture** choice (a new seam, control-flow, or contract), or
- **adds or changes a required daily-workflow step** (something every future turn
  now has to do).

**Trigger test:** does this alter FUTURE / system behavior, or only THIS turn's
output? Future/system behavior → triggered. **Non-triggers** (seam optional):
a one-off output, code already covered by Athena + tests, or a reversible scoped
edit. When triggered, set the plan line's `Decision-review:` field accordingly and
carry the disposition through to the commit trailer (`Decision-Review:` — enforced
by the commit-msg gate on the wiring surface).

This scopes the old standing rule `feedback-loki-challenge-every-decision`: it is
no longer "challenge EVERY decision" (which over-fired on one-off output) but
"challenge every decision on the trigger list above". That is the supersession —
the trigger list is the definition of "a decision worth the seam".

### Loki-first choice-ordering (TRIGGERED forks only)

When a triggered decision has a real fork, present options in a fixed order so the
adversary's pick is never buried:

1. **Loki's pick** (the option the adversarial voice argues for),
2. the **main-loop's pick** if different,
3. then any other options.

The chosen option is then re-run through Loki + Athena before it commits. This
ordering applies ONLY to triggered forks — exploratory or non-triggered choices
stay open-ended (don't force-rank a brainstorm).

Rules that make this bite:
- For **investigate / code-change / review / campaign**: name the workflow, OR if
  going manual, state up front where the adversarial seam (Loki challenge / Athena
  review) will run. "Manual, no seam" is not allowed — the seam is why the workflow
  exists. If you can't say where it runs, use the workflow.
- For **substantial/multi-part** requests: "Scribe: skipped" REQUIRES a reason
  (already-enumerated, already-precise). Silence is not a valid skip.
- Keep it tight — 3-4 lines. This is the human-in-the-loop gate, and now also the
  place the two most-skipped steps get surfaced instead of dropped.

**Why this is a mechanism, not a reminder:** the self-check already named Scribe as
"the one that gets skipped" and it got skipped anyway (2026-08-10 session — the Loki
seam nearly dropped, a human caught it, not the system). A passive end-of-turn check
fails silently. A required field in the plan line the user reads does not.

## Step 4: Act

- **Normal mode**: show the plan, wait for confirm, then execute.
- **Godspeed armed**: skip the confirm, execute immediately, report when done or
  when you hit a gate. (Check `~/.syndicate/.godspeed`.)
- **Always**: the prod gate, secrets gate, and precheck gate fire regardless of mode.

## Step 5: Record

- Any completed work → Ledger logs it (the SessionEnd hook does this automatically)
- Loki-raised concerns → logged, not blocking (Axiom 6)

## The Decision Tree (compressed)

```
request
 ├─ trivial/conversational/question? ────────────→ just answer (skip doctrine)
 │
 ├─ substantial/multi-part/vague? ───────────────→ SPAWN SCRIBE to recraft FIRST,
 │                                                  then classify the recrafted brief
 │
 ├─ fuzzy idea, don't know what to build? ───────→ Muse (/muse)
 ├─ something broken, cause unknown? ────────────→ syndicate-investigation
 ├─ read-only study/analyze/understand? ─────────→ syndicate-goalseek (Explore = probe)
 ├─ goal clear but plan unknown? ────────────────→ syndicate-goalseek
 ├─ 4+ known issues? ─────────────────────────────→ syndicate-campaign
 ├─ implement/fix/refactor (known)? ─────────────→ syndicate-pipeline
 ├─ review existing code? ───────────────────────→ syndicate-review
 └─ single-purpose (test/ship/infra/secrets/     ─→ that agent, directly
     track/message/convert)?
```

## Escalation & Halt (Legal Exits — Axiom 6)

Only stop mid-flow for:
1. Irreversible op needs approval (prod/destroy — Axiom 3)
2. Hard fault (tool down, API error)
3. User says "HALT!"
4. **A review-required commit with no pre-existing human waiver.** Under Godspeed,
   reaching a commit that touches the wiring surface (per the decision-trigger list)
   without an already-recorded `Decision-Review:` disposition or waiver = HALT and
   surface it to the human. Godspeed cannot self-issue the waiver — that's the point.
   - `waived=freeform:<reason>` also HALTs (freeform means "no structured category
     fit" — a human should see it). The structured categories
     (`test-only-fix`, `fix-of-reviewed`, `no-new-decision`, `self-repair`) do NOT
     HALT — they're pre-authorized dispositions.
   - Human-only-waiver is a doctrine + audit expectation, not a hard technical block:
     git cannot distinguish who authored a trailer, so the enforcement is the gate
     (trailer must be present) plus the audit trail (waiver counts surfaced by
     precheck), not machine-verified authorship.

Everything else → log a concern, continue. "I'm not sure" is not a stop condition.

## Self-Check (run this mentally each turn)

1. Was this substantial? → if so, did I recraft via Scribe BEFORE classifying?
   (This is the one that gets skipped. If you dispatched a raw multi-part prompt
   straight to agents, you skipped Step 0.5 — that's the bug.)
2. Did I classify, or did I just start doing? → classify first
2.5. **Am I about to do heavy work (a full investigation / multi-file build /
   review) MYSELF on Opus 4.8?** → STOP. Spawn the agent or workflow. Doing it
   in-loop is the 90%-Opus-4.8 trap (the Cost Directive). Light work stays in-loop.
3. Did the request match NO row? → don't freelance. Read-only study = research →
   goalseek. Still nothing? Recraft via Scribe and re-classify.
4. Am I using the toolkit, or reinventing it? → use the skill/workflow that exists
5. Am I the only one spawning? → yes (Axiom 11), unless I AM Odin/the session
6. Did I show the plan before acting? → yes, unless Godspeed
7. Will this get recorded? → yes, the Ledger (current-week.md)
8. **Was this a functional/wiring decision?** → if so, it must carry a recorded
   Loki→Athena disposition (or a waiver) before commit. The commit-msg gate
   enforces the trailer on the wiring surface; the plan line's `Decision-review:`
   field is where you declared it.
