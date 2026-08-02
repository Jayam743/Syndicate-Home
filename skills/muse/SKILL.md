---
name: muse
description: "Conception front-door — shape a raw idea into designed intent before building. Challenges, reframes, keeps a decision ledger."
---

# /muse — Conception & Shaping

The front-door before code. When you have an idea but haven't nailed down what
you actually want, Muse partners with you to shape it.

## Trigger

- `/muse` — start a conception session
- `/muse "the raw idea"` — start with an initial idea

e.g. `/muse "I want some kind of dashboard for the syndicate agents"`
e.g. `/muse "we should probably add caching somewhere"`

## When to Use

- You have a fuzzy idea and want to think it through before building
- You're not sure you're solving the right problem
- The design has forks you haven't resolved
- You want a record of WHY you made design decisions

## When NOT to Use

- The task is clear and simple → just `/route` it
- You already know exactly what to build → go straight to `/devspec` or Forge
- You're mid-execution → Muse is a front-door, not an interrupt

## The Flow

Muse (the agent) runs a four-phase conception:

1. **Understand** — what do you actually want? (the real goal, not just the words)
2. **Challenge & reframe** — simplest form? hidden assumptions? better framing? risks?
3. **Shape decisions** — one at a time, you lock each one
4. **Hand off** — to `/devspec`, Scribe→Forge, `/goalseek`, or `/campaign`

## The Partnership Rules

- **Muse challenges** — it won't just say yes. If the idea has a flaw or a simpler
  form, it surfaces it. That's the value.
- **You hold the gates** — Muse proposes decisions; you lock them. It never
  self-confirms on your behalf.
- **Decisions are append-only** — reversing a decision marks it superseded (numbered,
  with reasoning). Nothing is deleted. The history stays visible.

## Output

A decision ledger at `~/.syndicate/conception/YYYY-MM-DD-{slug}.md` containing:
- The real goal
- Every locked decision + reasoning + who decided
- Superseded decisions (kept for history)
- Open questions
- The handoff (what to execute next, and how)

## Invoke

```
Agent({
  subagent_type: "muse",
  prompt: "<the raw idea + any context>"
})
```

## Relationship to BJ's Workflow

Adapts BJ's `/muse` conception stage and its principles: equal partnership (AI
challenges/reframes, never just obeys), human authority (designer locks all gates),
and the append-only decision ledger (mistakes become superseded decisions, kept
numbered and attributed). In BJ's chain this precedes DDD/devspec; in Syndicate it
precedes any pipeline.
