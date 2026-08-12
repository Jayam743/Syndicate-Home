# Syndicate Model Configuration

## Tiering Principle — by ROLE, not by rank

The model an agent gets is decided by what it DOES, not by a fixed rank:

- **Think / plan / attack / reframe** → Opus (4.6–4.8). Reasoning that, if weak,
  produces subtly-wrong output that's expensive to catch.
- **Formula / rule-following / mechanical** → Sonnet 4.6 or Haiku 4.5. Running
  a known command, filling a template, converting a file.
- **Blast-radius exception:** an agent whose *operations* are formulaic but whose
  *mistakes* are costly/irreversible (infra, secrets, code that ships) stays on
  Opus even though the work looks mechanical. The token saving isn't worth a
  hard-to-reverse error.

## Agent Assignments

| Agent | Role type | Model | Fallback | Reason |
|-------|-----------|-------|----------|--------|
| **Odin** | orchestrate/route | Opus 4.8 | Opus 4.6 | Routing needs the strongest reasoning |
| **Muse** | conceive/reframe | Opus 4.8 | Opus 4.6 | Conception + challenge needs top tier |
| **Loki** | attack/argue | Opus 4.8 | Opus 4.6 | Devil's advocate needs top tier |
| **Specter** | investigate | Opus 4.8 | Opus 4.6 | Multi-angle diagnosis needs top tier |
| **Athena** | reason about bugs | Opus 4.7 | Opus 4.6 | Review accuracy is critical |
| **Forge** | write code | Opus 4.6 | session | Blast-radius: weak coders ship subtle bugs (Axiom 8) |
| **Scribe** | infer intent | Opus 4.6 | session | Recraft quality needs real reasoning |
| **Titan** | infra ops | Opus 4.6 | session | Blast-radius: wrong AWS action is costly/irreversible |
| **Safecracker** | secret ops | Opus 4.6 | session | Blast-radius: secrets are the highest-stakes surface |
| **Gauntlet** | run/write tests | Sonnet 4.6 | session | Running tests is mechanical; edge-case writing is backstopped by Athena/Loki/Specter |
| **Ledger** | log/format reports | Sonnet 4.6 | session | Tracking + report formatting is formula |
| **Hermes** | git commands | Haiku 4.5 | session | `git add/commit/push` — commands, not creativity |
| **Herald** | draft messages | Haiku 4.5 | session | Fill a template with provided content |
| **Cipher** | doc→markdown | Haiku 4.5 | session | `markitdown in.pdf > out.md` — mechanical |

**Cost note:** all Opus versions (4.6/4.7/4.8) are the SAME rate ($5/$25). Choosing
4.6 over 4.8 for Forge/Scribe/Titan/Safecracker does NOT cut the rate — it's a
capability-vs-token-usage choice within one price tier. Real rate savings come only
from dropping to Sonnet ($3/$15, −40%) or Haiku ($1/$5, −80%). The biggest lever of
all is not making Opus agents run when a cheaper agent (or the workflow) should —
see [[loki-review]] on delegation discipline.

## Why the mid/low tiers land where they do

- **Gauntlet → Sonnet 4.6:** running tests is pure rule-following; its one reasoning
  mode (designing edge cases) is a lighter version of what Athena/Loki/Specter already
  do at high tier, so it's backstopped.
- **Ledger → Sonnet 4.6:** scanning git logs and formatting a weekly report is
  structured formula work, not reasoning.
- **Hermes/Herald/Cipher → Haiku 4.5:** git commands, message templating, and file
  conversion are the most mechanical work in the crew. Haiku handles them at 1/5th
  the Sonnet rate. Don't pay to think about `git push`.

## Universal Fallback Policy

When BOTH primary and fallback models are unavailable:

```
Priority chain:
1. Primary model → use it
2. Primary unavailable → Fallback model → use it
3. Fallback unavailable → Session model (whatever CC is running) → use it + WARN

Warning format:
  ⚠ [agent-name] running on session model (fallback chain exhausted).
  Quality may be reduced. Token usage may differ from expected.
  Primary: [model] — unavailable
  Fallback: [model] — unavailable
  Using: [session model]
```

### What "session model" means

The model that Claude Code itself is running as (the one answering your messages).
This is always available — it's what YOU'RE talking to right now.

### Quality impact of degradation

| Agent | On primary | On fallback (4.6) | On session model |
|-------|-----------|-------------------|-----------------|
| Odin (routing) | Optimal routing, rare misroutes | Good routing, occasional wrong agent | Acceptable, may need correction |
| Forge (coding) | Precise, pattern-matching | Solid, slightly more verbose | Capable, may gold-plate |
| Athena (review) | Catches subtle bugs | Catches obvious bugs | May miss edge cases |
| Hermes (git) | Clean | Clean | Clean (git is git) |

### When does this trigger?

- Rate limiting (model temporarily unavailable)
- Account doesn't have access to a specific model
- Model deprecated/retired
- API outage for specific model tier

### Logging

Every fallback activation is logged for Loki's monthly review:
- Which agent
- Which model was unavailable
- What model was actually used
- Whether the output quality was acceptable

This data feeds Loki's improvement proposals (pattern: "Forge fell to session model 5 times this month — is our primary model flapping?")

## Model IDs (for frontmatter)

Syndicate targets **Bedrock inference-profile IDs** (this environment runs Claude
Code on AWS Bedrock). Plain Anthropic IDs like `claude-opus-4-7` are NOT valid here
and cause "invalid model identifier" errors — always use the `us.anthropic.*` form.

```
opus 4.8   → us.anthropic.claude-opus-4-8
opus 4.7   → us.anthropic.claude-opus-4-7
opus 4.6   → us.anthropic.claude-opus-4-6-v1
sonnet 4.6 → us.anthropic.claude-sonnet-4-6
haiku 4.5  → us.anthropic.claude-haiku-4-5-20251001-v1:0
```

**Verified available on this account** (via `aws bedrock list-inference-profiles`,
2026-08): opus 4.8, 4.7, 4.6, 4.5, 4.1; sonnet 5, 4.6, 4.5, 4; haiku 4.5; fable 5;
opus/sonnet 5. If porting Syndicate to a non-Bedrock (direct Anthropic API) setup,
switch these back to plain IDs (`claude-opus-4-8`, etc.).

## Fallback Rules

1. **Fallback stays in-family or drops to session** — opus→opus, sonnet→sonnet,
   haiku→haiku, or `session` for an agent already at the cheapest model we'd run it on.
2. **Never cross UP a tier on fallback** — a Haiku agent never falls back to Opus.
3. **`session` = the universal floor** — whatever model Claude Code is running is
   always available; it's the last resort when a specific model is rate-limited/down.
4. **Always warn on degradation** — user should know when quality might differ.
5. **Log every fallback** — Loki tracks patterns for monthly improvement proposals.
6. **Never silently degrade** — transparency over convenience.
