---
name: goalseek
description: "Open-ended goal-seeking — probe, judge sufficiency, steer, and journal until the goal is met or an escalation cord fires."
---

# /goalseek — Goal-Seeking Loop

For work where the GOAL is clear but the PLAN is not. Iterates toward *sufficiency*
rather than executing a known list of steps.

## Trigger

- `/goalseek "the goal"` — start seeking toward a target

e.g. `/goalseek "figure out why the nightly job intermittently hangs"`
e.g. `/goalseek "get a minimal repro of the memory leak"`
e.g. `/goalseek "find the best library for streaming CSV parse in this stack"`

## The Two Execution Modes (why this exists)

Syndicate has two fundamentally different ways to execute work. Conflating them is
a design error (this is BJ's executor-model insight):

| Mode | Skill / Workflow | Terminates when | Use for |
|------|-----------------|-----------------|---------|
| **Plan-execution** | `/campaign` (`campaign.js`) | The known plan is complete | You already have a list of issues/steps |
| **Goal-seeking** | `/goalseek` (`goalseek.js`) | A judge says "sufficient" (or escalation) | You have a target but not the steps |

**The chain:** open-ended goal → `/goalseek` → (if it emits a plan) → `/campaign` → artifact.
Goal-seeking discovers the plan; plan-execution runs it.

## The Loop

```
probe → judge sufficiency → steer → journal → (repeat until sufficient or cord fires)
```

1. **Probe** — one bounded attempt toward the goal (investigate, try, read, build)
2. **Judge** — is the goal met *well enough* to stop? (sufficiency, not perfection)
3. **Steer** — if not, what should the next probe focus on?
4. **Journal** — append what was learned (survives across rounds)

## The Escalation Cord

The loop does NOT run forever. It stops on:
- **Sufficiency** — the judge says "good enough" → emit result
- **Round budget** — hits `maxRounds` (default 6) → emit best-effort + mark unresolved
- **Diminishing returns** — 2+ rounds with flat/declining confidence → escalate to human

Escalation is not failure — it's the loop being honest that it's stopped making progress
and a human should decide the next move.

## Invoke the Workflow

```
Workflow({
  name: 'syndicate-goalseek',
  args: {
    goal: "why does the nightly job intermittently hang?",
    context: "starts around 2am, logs in /var/log/nightly, started ~last week",
    maxRounds: 6,
    agentType: "specter",   // specter for investigation, forge for build-toward-working
    emit: "answer"          // "answer" | "plan" | "artifact"
  }
})
```

## What It Emits

Based on `emit`:
- `answer` — a direct answer with confidence and caveats
- `plan` — ordered steps (may hand off to `/campaign` for execution)
- `artifact` — summary of files/outputs produced and their state

Every result includes `unresolved` (what's still open) and `handoff` (what should
run next, if anything).

## When NOT to Use

- You already know the exact steps → use `/campaign` or `/route` directly
- Single-shot question with an obvious answer → just route to an agent
- Irreversible operations mid-loop → those still hit the prod/secrets gates (Axiom 3)

## Relationship to BJ's Workflow

This adapts BJ's `/lazyriver` goal-seek loop (probe → judge → steer → journal) and
his executor-model distinction between plan-execution and goal-seeking. Simplified:
no separate MCP journal server — the journal lives in the workflow's own state and
in the returned result.
