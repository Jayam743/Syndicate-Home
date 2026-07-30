---
name: engage
description: "Session start ritual — introduce the crew, load state, confirm rules of engagement."
---

# /engage — Syndicate Session Start

Run this at the start of any session to orient the crew.

## Procedure

1. **Read project rules**: Read the project's CLAUDE.md (current directory)
2. **Check pipeline state**: Run `~/.syndicate/pipelines/current.json` — is there a pipeline to resume?
3. **Check godspeed**: Is a mandate active? Report its state.
4. **Check ledger**: What's in current-week.md? Brief the user on recent work.
5. **Report crew status**: Which agents are available (check `~/.claude/agents/*.md`)
6. **Detect environment**:
   - Git platform: `git remote get-url origin` → GitHub or GitLab?
   - Branch: `git branch --show-current`
   - Clean state: `git status --short`
7. **Confirm rules**: State the non-negotiables:
   - `/precheck` before every commit
   - Tests before push
   - No prod without approval
   - Agents ACT, don't ASK

## Output Format

```
═══ SYNDICATE ENGAGED ═══

Project: [name] ([platform])
Branch: [current branch]
State: [clean / N uncommitted changes]

Pipeline: [active pipeline stage / none]
Godspeed: [armed (turn X/N) / inactive]
Recent: [last 2-3 ledger entries]

Crew: 13 agents ready
Rules: precheck ✓ | test-gate ✓ | prod-gate ✓

Ready. What's the job?
```

## When BJ's Workflow is Also Present

If `/engage` from BJ's workflow exists (detected by `~/.claude/skills/engage/SKILL.md` being
a non-symlink or pointing outside Syndicate), defer to that one. Syndicate's engage
only runs in standalone mode.

## Notes

- This skill is OPTIONAL — the crew works without it
- It's useful for: resuming work after a break, confirming state, or starting fresh
- In BJ's workflow mode, use BJ's `/engage` instead (it includes plan loading)
