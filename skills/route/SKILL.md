---
name: route
description: "Route a task through Odin — the Syndicate orchestrator entry point."
---

# /route — Syndicate Task Router

Entry point for the Syndicate system. Pass any task and Odin routes it.

## Trigger

`/route <task description>`

e.g. `/route write a Python script that parses CSV files`
e.g. `/route review the changes on this branch`
e.g. `/route what did I do this week`

## Procedure

1. Pass the user's task to **Odin** (agent type: `odin`)
2. Odin classifies, optionally recrafts via Scribe, and dispatches to the right specialist
3. Report the result back to the user

## Implementation

```
Agent({
  subagent_type: "odin",
  prompt: "<user's task + any context from current session>"
})
```

## Notes

- If Odin is not installed, fall back to direct execution
- For simple/obvious tasks, Odin may skip Scribe and route directly
- Loki observation is automatic for Forge/Athena/Gauntlet/Titan tasks
