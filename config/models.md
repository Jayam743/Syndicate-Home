# Syndicate Model Configuration

## Model Tiers

| Tier | Primary | Fallback | Universal Fallback | Rule |
|------|---------|----------|-------------------|------|
| **1 — Command** | Opus 4.8 | Opus 4.6 | Session model + warn | These agents make decisions. |
| **2 — Execution** | Opus 4.7 | Opus 4.6 | Session model + warn | These agents do critical work. |
| **3 — Utility** | Sonnet 4 | Session model + warn | — | Formulaic work. Don't waste Sonnet 5 on git commands. |

## Agent Assignments

| Agent | Tier | Primary | Fallback | Reason |
|-------|------|---------|----------|--------|
| **Odin** | 1 | Opus 4.8 | Opus 4.6 | Routing requires strongest reasoning |
| **Loki** | 1 | Opus 4.8 | Opus 4.6 | Argumentation and pattern recognition |
| **Ledger** | 1 | Opus 4.8 | Opus 4.6 | Full context comprehension for tracking |
| **Specter** | 1 | Opus 4.8 | Opus 4.6 | Multi-angle investigation needs strongest reasoning |
| **Muse** | 1 | Opus 4.8 | Opus 4.6 | Conception/reframing needs strongest reasoning |
| **Forge** | 2 | Opus 4.7 | Opus 4.6 | Code quality needs strong model |
| **Athena** | 2 | Opus 4.7 | Opus 4.6 | Review accuracy is critical |
| **Gauntlet** | 2 | Opus 4.7 | Opus 4.6 | Test logic needs reasoning |
| **Titan** | 2 | Opus 4.7 | Opus 4.6 | Infra safety needs good judgment |
| **Safecracker** | 2 | Opus 4.7 | Opus 4.6 | Security-sensitive operations |
| **Scribe** | 2 | Opus 4.7 | Opus 4.6 | Prompt crafting requires intent inference |
| **Hermes** | 3 | Sonnet 4 | Session model | Git ops are formulaic commands |
| **Herald** | 3 | Sonnet 4 | Session model | Message drafting is straightforward |
| **Cipher** | 3 | Sonnet 4 | Session model | Document conversion is mechanical |

## Why Sonnet 4 for Tier 3?

Tier 3 agents do formulaic work:
- Hermes: `git add`, `git commit`, `git push`, `gh pr create` — commands, not creativity
- Herald: fill a template with content the user provided — formatting, not reasoning
- Cipher: run `markitdown input.pdf > output.md` — mechanical conversion

Sonnet 5 is overkill for this. Sonnet 4 handles these perfectly — same family, lower cost,
plenty of capability for structured/formulaic tasks. Don't waste the latest model on `git push`.

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
opus 4.8  → us.anthropic.claude-opus-4-8
opus 4.7  → us.anthropic.claude-opus-4-7
opus 4.6  → us.anthropic.claude-opus-4-6-v1[1m]   (session/1M-context form)
sonnet 4  → us.anthropic.claude-sonnet-4-5-20250929-v1:0
```

**Verified available on this account** (via `aws bedrock list-inference-profiles`,
2026-08): opus 4.8, 4.7, 4.6, 4.5, 4.1; sonnet 5, 4.6, 4.5, 4; haiku 4.5; fable 5;
opus/sonnet 5. If porting Syndicate to a non-Bedrock (direct Anthropic API) setup,
switch these back to plain IDs (`claude-opus-4-8`, etc.).

## Fallback Rules

1. **All Opus agents fall to Opus 4.6** — one shared fallback, no intermediate steps
2. **Sonnet agents fall to session model** — they're already running light work
3. **Universal fallback is always available** — it's the model you're talking to right now
4. **Always warn on degradation** — user should know when quality might differ
5. **Log every fallback** — Loki tracks patterns for monthly improvement proposals
6. **Never silently degrade** — transparency over convenience
