---
name: thoughts
description: "Stress-test a proposal — Loki + Specter argue before you commit to an approach."
---

# /thoughts — Genuine Alignment Check

When you're about to make a decision and want to stress-test it first.
Loki and Specter argue the proposal from different angles.

## Trigger

`/thoughts "proposal or question"`

e.g. `/thoughts "should we refactor the auth module to use JWT instead of sessions?"`
e.g. `/thoughts "is it safe to upgrade to Python 3.12 in this project?"`

## Procedure

1. **Present the proposal** clearly (what's being considered)

2. **Loki argues AGAINST** (devil's advocate):
   - What could go wrong?
   - What assumptions are unverified?
   - What's the blast radius if this fails?
   - Is there a simpler alternative?

3. **Specter investigates the evidence**:
   - What does the codebase actually say? (grep, read, check)
   - Are there dependencies that would break?
   - What's the real effort (not the optimistic estimate)?

4. **Synthesis**:
   - If both agree it's good → "Aligned. Proceed."
   - If Loki raises valid concerns → present them with mitigations
   - If Specter finds blockers → report them
   - If they disagree → present both views, let user decide

## Output Format

```
═══ THOUGHTS ═══

Proposal: [what's being considered]

Loki (against):
  • [concern 1]
  • [concern 2]

Specter (evidence):
  • [finding 1]
  • [finding 2]

Verdict: [aligned / concerns / blocked]
Recommendation: [proceed / proceed with mitigations / reconsider]
```

## When to Use

- Before large refactors
- Before architecture decisions
- Before choosing between approaches
- When "this feels right but I'm not sure"
- When Odin is about to route a complex task and wants validation

## When NOT to Use

- Simple/obvious decisions (just do it)
- Tasks already validated by tests (evidence exists)
- Style preferences (no right answer)
- Time-critical work under Godspeed (concerns are logged, not debated)
