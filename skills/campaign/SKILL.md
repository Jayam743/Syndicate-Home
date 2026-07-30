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
    maxWaves: 5
  }
})
```

### 3. Monitor and Report

The workflow runs autonomously. Each wave:
- Creates feature branches per issue
- Implements changes
- Runs tests
- Commits and pushes
- Creates PRs

Between waves: barrier ensures wave N completes before wave N+1 starts.

### 4. Final Report

```
═══ CAMPAIGN COMPLETE ═══

Issues: 4/4 complete
Waves: 3 (topology: mixed)
PRs created: #147, #148, #149, #150

Wave 1 (parallel): #123 ✓, #126 ✓
Wave 2 (serial):   #124 ✓
Wave 3 (serial):   #125 ✓

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
