---
name: godspeed
description: "Arm or disarm the autonomy mandate. Say 'godspeed' to flow, 'HALT!' to stop."
---

# /godspeed — Autonomy Mandate Control

Arms the Godspeed decaying-mandate system. When armed, pipelines flow without
per-step confirmation. Confidence decays over turns until checkpoint.

## Trigger

- `/godspeed` — arm the mandate (default 20 turns)
- `/godspeed 50` — arm with custom expected turns
- `/godspeed status` — show current mandate state
- `/godspeed halt` or `HALT!` — revoke immediately

## Procedure

### Arming (`/godspeed` or `/godspeed N`)

1. Run: `~/.syndicate/hooks/godspeed-arm.sh [N]` (or source inline)
2. Create mandate file at `~/.syndicate/.godspeed`
3. Reset turn counter at `~/.syndicate/.godspeed-state`
4. Report: "Mandate armed. Agents operating autonomously. HALT! to revoke."

### Status (`/godspeed status`)

1. Check `~/.syndicate/.godspeed` existence
2. Read turn counter from `~/.syndicate/.godspeed-state`
3. Calculate confidence: `bar = turns / expected_total`
4. Report: "Turn X/N, confidence at Y%. Next checkpoint at turn Z."

### Halting (`/godspeed halt` or `HALT!`)

1. Remove `~/.syndicate/.godspeed`
2. Remove `~/.syndicate/.godspeed-state`
3. Report: "Mandate revoked. All operations now require confirmation."

## What Godspeed Changes

| Without Godspeed | With Godspeed |
|------------------|---------------|
| Odin asks before routing | Odin routes immediately |
| Forge waits for confirm after coding | Forge reports, pipeline continues |
| Hermes asks before push | Hermes pushes (precheck still runs) |
| Loki challenges block | Loki challenges logged as concerns |

## What Godspeed NEVER Changes

- `/precheck` still runs before commit (Axiom 2)
- Test sentinel still required for push (Axiom 7)
- Prod mutations still need approval (Axiom 3)
- Secrets gate still armed (absolute)
- Specter still presents options (investigations need judgment)

## Decay Model

```
Confidence base: 80% if tests ran, 40% if not
Bar: turns_elapsed / expected_total
Checkpoint when: bar > confidence

Example (20 expected turns, tests ran):
  Turn 1-15: bar < 0.80 → flow freely
  Turn 16: bar = 0.80 → checkpoint
  User confirms → counter resets, mandate continues
```
