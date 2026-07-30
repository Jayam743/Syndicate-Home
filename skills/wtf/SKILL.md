---
name: wtf
description: "Start a troubleshooting flight recorder — Specter's investigation journal."
---

# /wtf — Flight Recorder for Investigations

When something is broken and you don't know why, `/wtf` starts a persistent
investigation journal. Findings survive session compaction and crashes.

## Trigger

- `/wtf` — start a new investigation
- `/wtf "description of the problem"` — start with context

## Procedure

1. **Create flight log**
   - Directory: `~/.syndicate/investigations/`
   - File: `YYYY-MM-DD-HH-MM-{slug}.md`
   - Initialize with: timestamp, problem description, initial symptoms

2. **Route to Specter** with investigation protocol:
   - Phase 1: Observe (read-only)
   - Phase 2: Hypothesize (2-4 theories)
   - Phase 3: Test (eliminate dead ends)
   - Phase 4: Argue (with Loki)
   - Phase 5: Present (options to user)

3. **Journal as you go**
   - Each hypothesis tested → entry in flight log
   - Each dead end eliminated → entry
   - Root cause found → entry
   - Options presented → entry

4. **Flight log format**

```markdown
# WTF: [problem description]
Started: YYYY-MM-DD HH:MM
Status: active | resolved | suspended

## Symptoms
- [what's broken]
- [when it started]
- [what changed]

## Timeline
- [HH:MM] Hypothesis: [theory]
- [HH:MM] Tested: [what was checked]
- [HH:MM] Eliminated: [dead end]
- [HH:MM] ROOT CAUSE: [what's actually wrong]

## Resolution
- Option chosen: [A/B/C]
- Fix applied: [what was done]
- Verified: [how we know it's fixed]
```

## Integration with MCP

If `mcp__wtf-server__*` tools are available (BJ's workflow installed):
- Use `wtf_freshell` to start (it has richer features)
- Use `wtf_now` to journal
- Use `wtf_happened` for timeline
- Use `wtf_imout` to suspend

If standalone (no MCP):
- Use the filesystem-based flight log above
- Specter manages the investigation
- Log persists in `~/.syndicate/investigations/`

## Companion Skills

- `/wtf-now` — add a manual journal entry
- `/wtf-happened` — generate timeline + runbook from the flight log
- `/wtf-imout` — suspend investigation (come back later)

## Why This Matters

Investigations are expensive. Without a flight log:
- You repeat dead ends across sessions
- You lose the thread after compaction
- You can't hand off to another person
- Ledger can't track investigation time

With a flight log:
- Every dead end is recorded (don't repeat it)
- Any session can resume (state on disk)
- Ledger knows "spent 45min diagnosing X"
- Loki can spot patterns (same component failing repeatedly)
