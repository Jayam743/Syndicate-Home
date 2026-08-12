---
name: syndicate
description: "Activate Syndicate self-dispatch on top of your current workflow. Run after /engage. After this, just talk — everything routes through Odin automatically."
---

# /syndicate — Activate the Crew

This is the entry point. Run it once per session (typically right after `/engage`)
to layer Syndicate on top of whatever workflow is already loaded — BJ's, your own,
or a bare session. After this, you don't type `/route` for everything: **you just
say what you want, and it flows through the dispatch doctrine automatically.**

## The intended flow

```
/engage      → load BJ's workflow (rules, plan, project state)
/syndicate   → layer Syndicate's self-dispatch on top (best of both worlds)
<just talk>  → "why is X crashing?" / "implement the profile feature" / "review this"
             → each request auto-classifies and routes through Odin. No prefixes.
```

## What this skill does

When invoked, DO ALL of the following, in order:

### 1. Read the dispatch doctrine
Read `config/doctrine.md` (in the Syndicate repo — find it via the `syndicate`
agent's location, or at `~/.claude/skills/syndicate/../../` sibling, or ask). This
is the decision brain. Internalize it — it governs every subsequent turn.

Also read `config/toolkit.md` so you know every skill/hook/workflow available.

### 2. Check state
- **Godspeed:** is `~/.syndicate/.godspeed` present? Report armed/inactive.
- **Resumable pipeline:** is `~/.syndicate/pipelines/current.json` present? If so,
  offer to resume it.
- **Coexistence:** is BJ's workflow active (did `/engage` run)? If so, note that
  Syndicate layers on top — BJ's gates/hooks still enforce; Syndicate adds routing.

### 3. Announce activation
Print a short banner so the user knows the crew is live:

```
═══ SYNDICATE ACTIVE ═══
Layered on: [BJ's workflow / standalone]
Self-dispatch: ON — just tell me what you want, no /route needed
Godspeed: [armed (turn X) / inactive]
Crew: 14 agents · 6 workflows · recall + oversight online
[resumable pipeline note, if any]
```

### 4. Enter self-dispatch mode (the important part)
From this point in the session, treat EVERY subsequent user message as input to the
dispatch doctrine. On each turn:

1. **Classify** the request (doctrine Step 1 — conceive/investigate/goal-seek/
   campaign/code-change/review/single-agent/trivial)
2. **Recall** prior context for investigate/goal-seek/code-change/review/campaign
   (run `~/.syndicate/scripts/recall.sh --repo <cwd> "<request>"` and fold in the brief)
3. **Show the one-line plan** (`→ [classification] → [path]`)
4. **Act** — route to the agent/workflow, or auto-act if Godspeed is armed
5. **Record** — evidence packet + Ledger

Do NOT wait for `/route`. Routing is now your default behavior for the rest of
the session. The user talks normally; you orchestrate.

## Precedence with BJ's workflow

Syndicate layers ON TOP, it does not replace:
- BJ's safety gates (test-gate, secrets-gate, prod stop-hook) still fire and still win
- BJ's `/precheck`, `/scp`, `/wtf` are used as-is (Syndicate defers to them)
- Syndicate adds: classification, agent routing, recall, workflows, oversight
- If BJ's doctrine and Syndicate's ever conflict, **BJ's safety rules win** (Axiom 3)

## Notes

- Run once per session. Running again just re-affirms the mode (harmless).
- The SessionStart hook (`session-start-syndicate.sh`) auto-activates this on fresh
  sessions — so `/syndicate` is mainly for: (a) sessions that started before the
  hook, (b) explicitly re-arming after a compact, or (c) your muscle-memory flow
  after `/engage`.
- To stand down: say "stand down Syndicate" and revert to manual `/route` only.
