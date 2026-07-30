---
name: assesswaves
description: "Assess whether work justifies wave-pattern campaign execution."
---

# /assesswaves — Campaign Suitability Assessment

Quick check: should this work be campaigned (waves) or done one-by-one?

## Trigger

`/assesswaves` — assesses the current set of work items

## Criteria (all must be true for campaign to be justified)

1. **Count >= 4 issues** — fewer than 4 isn't worth campaign overhead
2. **Shared context** — issues relate to each other (same feature area, same component)
3. **Dependency graph exists** — at least some issues depend on others
4. **Single repo** — campaign targets one repository (cross-repo = serial phases)
5. **Non-trivial wall-clock** — each issue takes > 5 minutes (trivial items = just do them)

## Output

```
═══ WAVE ASSESSMENT ═══

Issues: [N]
Shared context: [yes/no — what connects them]
Dependencies: [N items have deps, graph depth = M]
Single repo: [yes/no]
Per-item effort: [trivial / moderate / substantial]

VERDICT: [CAMPAIGN JUSTIFIED / NOT JUSTIFIED]
Reason: [one-line explanation]

Recommended topology: [serial / parallel / mixed]
Estimated waves: [N]
```

## If NOT Justified

Suggest the alternative:
- "Just run standard pipeline per issue (< 4 items)"
- "Issues are independent — no wave structure needed, just parallel agents"
- "Cross-repo — use serial phases, not a single campaign"

## If JUSTIFIED

Suggest next step:
- "Ready for `/campaign [issue-ids]` — or prep manually with `/prepwaves`"

## Notes

- This assessment is FAST (read-only, no execution)
- It doesn't modify anything — just evaluates
- In BJ's workflow mode, defer to BJ's `/assesswaves` (more comprehensive)
- The threshold is 4 issues — this is from BJ's Axiom 7: "count >= 4, or non-trivial wall-clock"
