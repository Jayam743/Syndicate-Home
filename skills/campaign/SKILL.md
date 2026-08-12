---
name: campaign
description: "Multi-issue wave execution — decompose work into dependency waves and execute autonomously."
---

# /campaign — Wave-Pattern Campaign Execution

Execute multiple related issues as a campaign. Decomposes into dependency waves,
executes items within each wave in parallel, enforces barriers between waves.

## Trigger

- `/campaign` — interactive: walks you through issue selection
- `/campaign [issue-ids...]` — direct: specify issues to campaign

## When to Use

- You have 4+ related issues to implement
- The issues have dependency relationships (some must finish before others start)
- You want autonomous batched execution (minimal human gates)
- You've already assessed suitability with `/assesswaves`

## When NOT to Use

- Fewer than 4 issues (just use standard pipeline per issue)
- Issues span multiple repos (campaign targets one repo)
- Issues are completely unrelated (no shared dependency graph)

## Procedure

### 1. Gather Issues

If invoked without issue IDs, ask user:
- Which issues? (by number, URL, or description)
- Which repo? (auto-detect from cwd if possible)
- Base branch? (default: current branch)
- Auto-merge small PRs? (default: no)

### 2. Invoke Campaign Workflow

```
Workflow({
  name: 'syndicate-campaign',
  args: {
    issues: [
      { id: "123", title: "Add user avatar upload", description: "...", dependencies: [] },
      { id: "124", title: "Avatar resizing service", description: "...", dependencies: ["123"] },
      { id: "125", title: "Avatar in profile page", description: "...", dependencies: ["124"] },
      { id: "126", title: "Update API docs", description: "...", dependencies: [] }
    ],
    repo: "/path/to/repo",
    branch: "main",
    autoMerge: false,
    maxWaves: 5,
    intent: "the overall goal of this whole batch (what it's FOR)",
    priorContext: "<paste the recall brief here — run ~/.syndicate/scripts/recall.sh first>",
    overseeConfidenceFloor: 50
  }
})
```

**Fill `intent` and `priorContext`.** Before launching, Odin runs
`~/.syndicate/scripts/recall.sh "<the batch goal>"` and passes the result as `priorContext`.
The oversight seam uses both to judge whether the campaign is still on the rails.

### 3. Monitor and Report

The workflow runs autonomously. Each wave:
- Creates feature branches per issue
- Implements changes
- Runs tests
- Commits and pushes
- Creates PRs

Between waves: barrier ensures wave N completes before wave N+1 starts.

### The Oversight Seam (between waves)

After each wave PASSES — and before the next begins — a distinct **campaign
overseer** judges the trajectory: *"Given the intent, the work shipped so far, and
prior related sessions, is it safe to continue?"* It returns
`{continue, confidence, concern, recommendation}`.

The campaign **HOLDs** (a Legal Exit, Axiom 6) if the overseer says `continue:false`
OR confidence drops below `overseeConfidenceFloor` (default 50). A HOLD is a
considered stop with a recommendation — not a hard fault.

Why this matters: per-item review catches bugs in one change. The overseer catches
**drift** — the batch quietly pulling away from what you actually wanted, or repeating
a mistake visible in prior sessions. The overseer is its OWN agent at campaign
altitude (not a reused execution agent), and it sees the recall/history context.

### Dispatch Classification (serial vs parallel within a wave)

Items in a wave have no dependencies on each other — but that does NOT mean they
should always run in parallel. The decomposition classifies each wave's dispatch:

| Dispatch | When | Behavior |
|----------|------|----------|
| `serialize` | **Default.** Width-1 wave, overlapping files, or any doubt | Items run one at a time |
| `fan` | Items are VERIFIED independent (disjoint files) AND mechanical | Items run concurrently |
| `serialize-preferred` | Items look independent but involve discovery/learning | Serial, so early findings inform later items |

**The bias is asymmetric (borrowed from BJ's dispatch model):**
> A wrong `serialize` only costs wall-clock. A wrong `fan` can invalidate the whole
> wave — two agents editing overlapping files clobber each other's work.

So the campaign defaults to serial and only fans out when it's confident the items
are truly independent. Width-1 waves are always serial regardless of classification.

### 4. Final Report

```
═══ CAMPAIGN COMPLETE ═══

Issues: 4/4 complete
Waves: 3 (topology: mixed)
PRs created: #147, #148, #149, #150

Wave 1 (fan):       #123 ✓, #126 ✓   (verified independent + mechanical)
Wave 2 (serialize): #124 ✓
Wave 3 (serialize): #125 ✓

Concerns raised: 1 (non-blocking, logged)
Duration: ~12 minutes
```

## Legal Exits (from SYNDICATE_AXIOMS.md)

Campaign stops ONLY for:
1. Hard fault (tool unavailable, API down)
2. Security/prod risk (Axiom 3)
3. Explicit user halt ("HALT!")

Everything else is a concern — logged and continued.

## Relationship to BJ's Wave Pattern

This is Syndicate's adaptation of BJ's workflow wave pattern:
- Same concept: decompose → dependency-order → parallel within wave → barrier between
- Simplified: no kahuna integration branch (single-repo, PRs to main/release)
- No per-wave human gate by default (godspeed assumed for campaigns)
- Circular dependency detection halts at decomposition (before execution)

For BJ's full wave tooling (with MCP integration, SDLC server, trust gates):
use `/prepwaves` → `/nextwave` or `/wavemachine` from BJ's workflow directly.
