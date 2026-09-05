# Syndicate Model Configuration

## Subscription aliases (home)

This branch targets the operator's **home machine on the Anthropic Pro subscription**
(claude.ai login). Subscriptions accept only the three model **aliases** — the harness
resolves each to a concrete model. Full/Bedrock model ids and 1M-context
inference-profile suffixes do NOT work on a subscription — use the alias, nothing else.

```
opus    → think band   (orchestrate / decide / attack / investigate / review)
sonnet  → formula band (formulated execution from a decided spec)
haiku   → mechanical band (commands / templates / conversion)
```

### Tier table

| Band | Alias | Agents |
|------|-------|--------|
| think | `opus` | odin, muse, loki, scribe, specter, athena |
| formula | `sonnet` | forge, gauntlet, ledger, titan, safecracker |
| mechanical | `haiku` | hermes, herald, cipher |

Operator intent: **Opus thinks/decides, Sonnet does formulated work, Haiku is
mechanical.** Forge/Titan/Safecracker sit in the formula band — they execute from a
decided spec, and keeping them on Sonnet conserves scarce Opus quota (see the Quota
Directive in `config/doctrine.md`).

## Band Assignments

### THINK band (`opus`)

Agents whose reasoning errors are subtle and expensive to catch.

| Agent | Role | Why think-band |
|-------|------|----------------|
| **Odin** | orchestrate/route | Routing needs strongest reasoning |
| **Muse** | conceive/reframe | Conception + challenge needs top tier |
| **Loki** | attack/argue | Devil's advocate needs top tier |
| **Scribe** | infer intent | Recraft quality needs real reasoning |
| **Specter** | investigate | Multi-angle diagnosis needs top tier |
| **Athena** | review/bugs | REVIEW-DIVERSITY design (see below) |

**Athena review-diversity:** Athena's PRIMARY reviewer is `opus` — the full review gate
runs there. On **high-stakes or security diffs**, a CONDITIONAL decorrelated SECOND-PASS
review runs on `sonnet`. Same-family review means correlated blind spots ("diversity
theater"); a different family is real cross-family decorrelation. The second pass is a
**review-workflow behavior** (documented here and in `agents/athena.md`), NOT a
frontmatter fallback.

### FORMULA band (`sonnet`)

Agents doing structured, formulated work from a decided spec.

| Agent | Role | Why formula-band |
|-------|------|------------------|
| **Forge** | write code | Executes a decided spec; review-backstopped by Athena/Loki |
| **Gauntlet** | run/write tests | Running tests is mechanical; edge-case design backstopped by Athena/Loki |
| **Ledger** | log/format reports | Tracking + report formatting is formula |
| **Titan** | local dev/system ops | Bounded local operations from a decided plan |
| **Safecracker** | local secret hygiene | Bounded, checklist-driven local secret work |

### MECHANICAL band (`haiku`)

Agents executing pure commands/templates with no reasoning required.

| Agent | Role | Why mechanical-band |
|-------|------|---------------------|
| **Hermes** | git commands | `git add/commit/push` — commands, not creativity |
| **Herald** | draft messages | Fill a template with provided content |
| **Cipher** | doc conversion | `markitdown in.pdf > out.md` — mechanical |

## Fallback Policy

Every agent declares `fallback_model: none`. On a subscription the alias resolves
directly; there is no cheaper cross-tier profile to fall to and no honest "session"
no-op (the session IS the resolved model). If an alias fails to resolve, fail loud
rather than silently running on a different tier.

**Install-time check (home):** confirm whether Pro grants Opus before trusting the think
band — run `/model` and `/usage`, and set `model: opus` on one agent to confirm it
resolves. If Pro rejects Opus, flip the think band to `sonnet` (a one-line, documented
change). Aliases make this safe either way. See the branch README post-install step.

## Workflow agent() model overrides

Workflow stages spawned via `agent()` inherit the **main-loop model** unless an explicit
`model:` is passed. To stop the mechanical/formula stages from silently running on the
think-tier main-loop model, the workflows downshift specific stages via a `BAND` const
(band name → alias):

| Stage | Band | Alias |
|-------|------|-------|
| `recall:prime` | mechanical | `haiku` |
| `gauntlet:test` | formula | `sonnet` |
| `hermes:ship` | mechanical | `haiku` |
| `ledger:record` | formula | `sonnet` |

`recall:prime` is a mechanical shell-out (run recall.sh, return stdout verbatim), so it
is downshifted to `haiku` in every workflow that has it. Reasoning / blast-radius stages
(`scribe:recraft`, `forge:implement`, `athena:review`, `specter`, `loki`,
`odin:decompose`) inherit the main-loop model — do not downshift them.

**Rules:**
- Prefer the band name / `agentType` over a hardcoded alias (`model: BAND.sonnet`).
- Every `model:` **string literal** under `workflows/*.js` must be one of the 3 aliases
  (`opus`/`sonnet`/`haiku`) — enforced by `scripts/ci/validate.sh`.

## Main-loop / Agent-tool spawns

When the MAIN LOOP (or any ad-hoc dispatch) spawns a specialist via the **Agent tool**,
pass the `model` override so mechanical/formula work does NOT inherit the think tier:

| Spawn tier | Agents | Agent-tool `model` |
|-----------|--------|--------------------|
| mechanical | hermes, cipher, herald | `haiku` |
| formula | forge, gauntlet, ledger, titan, safecracker | `sonnet` |
| think | odin, muse, scribe, athena, specter, loki | *(omit → inherits main-loop model)* |

The Agent tool's `model` takes an **alias enum** (`haiku`/`sonnet`/`opus`) and the
harness resolves it. Never pass a raw/Bedrock id — it will not resolve on a subscription.

## Model audit

The SessionEnd model-audit (`hooks/session-end-model-audit.sh`) still runs: it proves
each subagent ran on its intended alias by comparing the agent's frontmatter alias
against the model family that actually ran. See `config/model-audit.md`.
