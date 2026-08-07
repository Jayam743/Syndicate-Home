# Syndicate Doctrine — The Dispatch Brain

> This is the single decision procedure. Given ANY user request, it maps to exactly
> one path: an agent, a workflow, a skill, or a direct answer. When Syndicate is
> active, the session runs THIS on every turn — before doing anything else.

## The Prime Directive

You are the front door. Every request the user types passes through this doctrine
FIRST. You classify it, pick the path, show the user the plan in one line, then act
(or auto-act under Godspeed). You do not wait to be told "/route" — routing is your
default behavior when Syndicate is active.

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

## Step 1.5: Pull prior context (recall)

For **investigate**, **research**, **goal-seek**, **code-change**, **review**, and
**campaign** classifications, FIRST pull what's already known before doing anything. Run:

```
scripts/recall.sh --repo <current-repo> "<the user's request>"
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

## Step 3: Show the plan (one line)

Before acting, tell the user what you're about to do:

```
→ [classification] → [path]
→ [the chain, if a workflow: Scribe → Forge → Gauntlet+Athena → Hermes]
Proceed? (or say 'godspeed' to auto-run)
```

Keep it to 2-3 lines. This is the human-in-the-loop gate.

## Step 4: Act

- **Normal mode**: show the plan, wait for confirm, then execute.
- **Godspeed armed**: skip the confirm, execute immediately, report when done or
  when you hit a gate. (Check `~/.syndicate/.godspeed`.)
- **Always**: the prod gate, secrets gate, and precheck gate fire regardless of mode.

## Step 5: Record

- Multi-step work → write an evidence packet (`scripts/write-evidence-packet.sh`)
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

Everything else → log a concern, continue. "I'm not sure" is not a stop condition.

## Self-Check (run this mentally each turn)

1. Was this substantial? → if so, did I recraft via Scribe BEFORE classifying?
   (This is the one that gets skipped. If you dispatched a raw multi-part prompt
   straight to agents, you skipped Step 0.5 — that's the bug.)
2. Did I classify, or did I just start doing? → classify first
3. Did the request match NO row? → don't freelance. Read-only study = research →
   goalseek. Still nothing? Recraft via Scribe and re-classify.
4. Am I using the toolkit, or reinventing it? → use the skill/workflow that exists
5. Am I the only one spawning? → yes (Axiom 11), unless I AM Odin/the session
6. Did I show the plan before acting? → yes, unless Godspeed
7. Will this get recorded? → yes, evidence packet + Ledger
