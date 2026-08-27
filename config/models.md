# Syndicate Model Configuration

## 3-Band / 4-Pin Architecture

This account runs on AWS Bedrock with a **hard limit of 4 pinned model slots**.
Agents are assigned to one of 3 bands; each band maps to a pinned model.

### Pinned set (exactly 4 — Bedrock hard limit)

```
opus-4-8   → us.anthropic.claude-opus-4-8
opus-4-7   → us.anthropic.claude-opus-4-7
sonnet-4-6 → us.anthropic.claude-sonnet-4-6
haiku-4-5  → us.anthropic.claude-haiku-4-5-20251001-v1:0
```

**opus-4-6 was DROPPED from the pin set.** Opus 4.8 covers it at the same $5/$25 rate
(no cost difference). This freed the 4th slot for Haiku 4.5, which was previously
falling back to Opus 4.8 (8x cost inversion).

> **REQUIRED OPERATOR ACTION:** Re-pin Bedrock to swap `us.anthropic.claude-opus-4-6-v1`
> out of the inference-profile set and add `us.anthropic.claude-haiku-4-5-20251001-v1:0`
> in its place. Until this is done, Haiku agents will continue to resolve to Opus 4.8.

### Bug fixed (2026-08-26)

Empirically verified via resolution probes that Haiku 4.5 was falling to Opus 4.8
(8x cost inversion) because Opus occupied 3 of 4 pin slots (4.8, 4.7, 4.6). Collapsing
to 2 Opus pins frees the slot for Haiku.

## Band Assignments

### THINK band (Opus 4.8, fallback Opus 4.7)

Agents whose reasoning errors are subtle and expensive to catch.

| Agent | Role | Why think-band |
|-------|------|----------------|
| **Odin** | orchestrate/route | Routing needs strongest reasoning |
| **Muse** | conceive/reframe | Conception + challenge needs top tier |
| **Loki** | attack/argue | Devil's advocate needs top tier |
| **Specter** | investigate | Multi-angle diagnosis needs top tier |
| **Forge** | write code | Blast-radius: weak coders ship subtle bugs |
| **Scribe** | infer intent | Recraft quality needs real reasoning |
| **Titan** | infra ops | Blast-radius: wrong AWS action is costly/irreversible |
| **Safecracker** | secret ops | Blast-radius: secrets are highest-stakes surface |
| **Athena** | review/bugs | REVIEW-DIVERSITY exception (see below) |

**Athena exception:** model=opus-4-7, fallback=opus-4-8. Athena's primary is
intentionally different from Odin/Loki/Forge so the reviewer sees code with a
different model's perspective than the one that wrote/routed it. This is the
"review-diversity" principle.

> **Opus 4.7's pin is LOAD-BEARING** — it is both the think-band fallback (for all
> other think agents) AND Athena's review-diversity primary. Do not displace without
> re-solving review diversity.

### FORMULA band (Sonnet 4.6, fallback Haiku 4.5)

Agents doing structured, rule-following work backstopped by think-band agents.

| Agent | Role | Why formula-band |
|-------|------|------------------|
| **Gauntlet** | run/write tests | Running tests is mechanical; edge-case design backstopped by Athena/Loki |
| **Ledger** | log/format reports | Tracking + report formatting is formula |

### MECHANICAL band (Haiku 4.5, fallback session)

Agents executing pure commands/templates with no reasoning required.

| Agent | Role | Why mechanical-band |
|-------|------|---------------------|
| **Hermes** | git commands | `git add/commit/push` — commands, not creativity |
| **Herald** | draft messages | Fill a template with provided content |
| **Cipher** | doc conversion | `markitdown in.pdf > out.md` — mechanical |

## Fallback Policy (by band)

```
THINK band:
  opus-4-8 → opus-4-7 → session + WARN
  (Athena: opus-4-7 → opus-4-8 → session + WARN)

FORMULA band:
  sonnet-4-6 → haiku-4-5 → session + COST-WARN

MECHANICAL band:
  haiku-4-5 → session + COST-WARN
```

**session = Opus 4.8 on this account**, so a formula/mechanical agent reaching
session is a **COST-INCREASE event** (an acknowledged exception to never-cross-up,
because session is the only universal floor) — log it loudly, never silently.

### Logging

Every fallback activation is logged for Loki's monthly review:
- Which agent
- Which model was unavailable
- What model was actually used
- Whether the output quality was acceptable

## Deliberate Trade: 1M-context dropped

The `[1m]` 1M-context long-context fallback (previously on Odin/Loki/Muse/Specter/Athena)
is **dropped** — no 1M variant is pinned. Future long-context tasks must plan around
this limitation (e.g., chunking, summarization before agent dispatch).

## Cost Note

All Opus versions (4.7/4.8) are the SAME rate ($5/$25). Choosing between them is a
capability/diversity choice, not a cost choice. Real rate savings come only from
dropping to Sonnet ($3/$15, -40%) or Haiku ($1/$5, -80%). The biggest lever of all
is not making Opus agents run when a cheaper agent (or the workflow) should — see
[[loki-review]] on delegation discipline.

## Workflow agent() model overrides

Workflow stages spawned via `agent()` inherit the **main-loop model (Opus 4.8)** unless
an explicit `model:` is passed. To stop the mechanical stages from silently running on
Opus, `workflows/standard-pipeline.js` downshifts exactly three stages via a `BAND`
const (band-name → pinned id):

| Stage | Band | Pinned id |
|-------|------|-----------|
| `gauntlet:test` | sonnet | `us.anthropic.claude-sonnet-4-6` |
| `hermes:ship` | haiku | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `ledger:record` | sonnet | `us.anthropic.claude-sonnet-4-6` |

Reasoning / blast-radius stages (`scribe:recraft`, `forge:implement`, `athena:review`,
and the `recall` pre-stage) are intentionally **left on the default (Opus)** — do not
downshift them. Each downshifted stage also sets `agentType` (persona) and `log()`s its
intended model so the transcript shows the tier.

**Rules:**
- Prefer the band name / `agentType` over hardcoded ids (`model: BAND.sonnet`, not a raw
  string).
- Every `model:` **string literal** under `workflows/*.js` must be one of the 4 pinned
  ids — enforced by `scripts/ci/validate.sh` (fails CI otherwise, closing the
  400-on-unpinned-id door).

**COVERAGE BOUNDARY:** This only covers **workflow-internal mechanical stages**. Ad-hoc
**main-loop** spawns (e.g. `general-purpose` / `Explore` subagents) still inherit
Opus 4.8 and are **NOT** fixed here — route those through the #4-family work / Cost
Directive on delegation discipline. Issue #13 is **not** "the fix for 100%-Opus."

## Bedrock Model IDs (inference-profile form)

```
opus 4.8   → us.anthropic.claude-opus-4-8
opus 4.7   → us.anthropic.claude-opus-4-7
sonnet 4.6 → us.anthropic.claude-sonnet-4-6
haiku 4.5  → us.anthropic.claude-haiku-4-5-20251001-v1:0
```

**Caveat (from BJ's workflow):** The Claude Code "Monitor" primitive and `--channels`
are gated OFF on Bedrock. Current Loki-observe and Astrolabe tiles use hooks/polling,
so they are unaffected. Any FUTURE agent relying on background monitoring must account
for this limitation.

**Verified available on this account** (via `aws bedrock list-inference-profiles`,
2026-08): opus 4.8, 4.7, 4.6, 4.5, 4.1; sonnet 5, 4.6, 4.5, 4; haiku 4.5; fable 5;
opus/sonnet 5. If porting Syndicate to a non-Bedrock (direct Anthropic API) setup,
switch to plain IDs (`claude-opus-4-8`, etc.).

## Future Consideration

Sonnet 5 is a possible upgrade for the formula band PENDING rate verification. Do not
pin an unknown-rate model into the cost-control band without confirming it stays at or
below the $3/$15 Sonnet rate.
