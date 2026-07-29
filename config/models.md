# Syndicate Model Configuration

## Model Tiers

| Tier | Primary | Fallback | Rule |
|------|---------|----------|------|
| **1 — Command** | opus 4.8 | opus 4.7 | Never falls to sonnet. These agents make decisions. |
| **2 — Execution** | opus 4.7 | opus 4.6 | Never falls to sonnet. These agents do critical work. |
| **3 — Utility** | sonnet 5 | sonnet 4 | Never falls to haiku. These agents do mechanical work. |

## Agent Assignments

| Agent | Tier | Primary | Fallback | Reason |
|-------|------|---------|----------|--------|
| **Odin** | 1 | opus 4.8 | opus 4.7 | Routing requires strongest reasoning |
| **Loki** | 1 | opus 4.8 | opus 4.7 | Argumentation and pattern recognition |
| **Ledger** | 1 | opus 4.8 | opus 4.7 | Needs full context comprehension for tracking |
| **Specter** | 1 | opus 4.8 | opus 4.7 | Multi-angle investigation needs strongest reasoning |
| **Forge** | 2 | opus 4.7 | opus 4.6 | Code quality needs strong model |
| **Athena** | 2 | opus 4.7 | opus 4.6 | Review accuracy is critical |
| **Gauntlet** | 2 | opus 4.7 | opus 4.6 | Test logic needs reasoning |
| **Titan** | 2 | opus 4.7 | opus 4.6 | Infra safety needs good judgment |
| **Safecracker** | 2 | opus 4.7 | opus 4.6 | Security-sensitive operations |
| **Scribe** | 2 | opus 4.7 | opus 4.6 | Prompt crafting requires intent inference, not just formatting |
| **Hermes** | 3 | sonnet 5 | sonnet 4 | Git ops are formulaic |
| **Herald** | 3 | sonnet 5 | sonnet 4 | Message drafting is straightforward |
| **Cipher** | 3 | sonnet 5 | sonnet 4 | Document conversion is mechanical |

## Fallback Rules

1. **Same family only** — opus never falls to sonnet, sonnet never falls to haiku
2. **Automatic** — if primary model is unavailable or rate-limited, use fallback
3. **Log it** — Loki tracks every time a fallback is used (potential improvement signal)
4. **Never upgrade without approval** — fallback goes DOWN only, never up

## Model IDs (for frontmatter)

```
opus 4.8  → claude-opus-4-8
opus 4.7  → claude-opus-4-7
opus 4.6  → us.anthropic.claude-opus-4-6-v1[1m]
sonnet 5  → claude-sonnet-5
sonnet 4  → claude-sonnet-4-5-20251022
```
