---
name: status
description: "Generate a weekly status report via Ledger."
---

# /status — Weekly Status Report

Quick entry point to generate your weekly status report.

## Trigger

`/status` — defaults to last Wednesday through today
`/status 2026-07-15 2026-07-22` — custom date range

## Procedure

1. Pass to **Ledger** (agent type: `ledger`)
2. Ledger scans git logs across all repos, session transcripts, and MR history
3. Returns formatted status report ready to paste

## Implementation

```
Agent({
  subagent_type: "ledger",
  prompt: "Generate weekly status report for [date range]. Scan all repos under /mnt/c/Users/jpatel/blueshift-devkit/ for commits by Jayam/jpatel/Jbpatel. Format as: Accomplishments (grouped by theme with bullet points), Blockers (with mitigations), On track assessment."
})
```
