# Syndicate Model Configuration

## 3-Band / 4-Pin Architecture

This account runs on AWS Bedrock with a **hard limit of 4 pinned model slots**.
Agents are assigned to one of 3 bands; each band maps to a pinned model.

### Pinned set (3 live + 1 dead slot)

```
opus-4-8[1m] → us.anthropic.claude-opus-4-8[1m]                (think band)
sonnet-5[1m] → us.anthropic.claude-sonnet-5[1m]                (formula band; Athena 2nd-pass)
haiku-4-5    → us.anthropic.claude-haiku-4-5-20251001-v1:0     (mechanical band; 200K ctx — bare)
─────────────────────────────────────────────────────────────
[4th slot]   → fable 5 — ORG-BLOCKED, permanently unavailable this session (DEAD)
```

**CRITICAL — [1m] suffixes are load-bearing.** Only the `[1m]` inference profiles are
pinned for opus and sonnet, so every agent `model:` id for those bands MUST carry the
`[1m]` suffix verbatim — a bare `us.anthropic.claude-opus-4-8` will NOT resolve. Haiku
is 200K-context and has no `[1m]` variant, so it stays bare.

**opus-4-7 and opus-4-6 are NO LONGER PINNED.** sonnet-4-6 is replaced by sonnet-5.
Haiku 4.5 is now pinned (no longer inverting to Opus).

> **STANDING RE-PIN TODO (Fork B):** The 4th Bedrock slot is currently DEAD — `fable 5`
> is org-blocked and unavailable this session. No fallback logic may depend on a 4th
> slot. Revisit if the org unblocks fable, or if a custom pin becomes possible — a live
> 4th slot could host a distinct reviewer or a specialized model. Until then: 3 live pins.

## Band Assignments

### THINK band (Opus 4.8 `[1m]`, fallback NONE — fail loud)

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
| **Athena** | review/bugs | REVIEW-DIVERSITY design (see below) |

**Athena review-diversity (Fork A):** Athena's PRIMARY reviewer is Opus 4.8
(`us.anthropic.claude-opus-4-8[1m]`, `fallback_model: none`) — the full review gate
runs there. On **high-stakes or security diffs**, a CONDITIONAL decorrelated
SECOND-PASS review runs on **Sonnet 5** (`us.anthropic.claude-sonnet-5[1m]`).

Rationale (recorded): the old opus-4.7-vs-4.8 split was never real review diversity —
same model family means correlated blind spots ("diversity theater"). Sonnet 5 is a
genuinely different family, so it is real cross-family decorrelation, and it is cheap
($2/$10) — we get a second independent set of eyes on the diffs that matter WITHOUT
downgrading the primary Opus gate. The second pass is a **review-workflow behavior**
(documented here and in `agents/athena.md`), NOT a frontmatter fallback — think-band
frontmatter has no fallback (fail loud).

### FORMULA band (Sonnet 5 `[1m]`, fallback Haiku 4.5)

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
  opus-4-8[1m] → NONE (fail loud)
  (Athena: same — opus-4-8[1m] → NONE; Sonnet-5 2nd-pass is a workflow behavior, not a fallback)

FORMULA band:
  sonnet-5[1m] → haiku-4-5 → session + COST-WARN

MECHANICAL band:
  haiku-4-5 → session + COST-WARN
```

**Fork D — think band fails LOUD, no fallback.** `session` IS Opus 4.8 on this account,
so an `opus-4-8 → session` failover is a **dishonest no-op** (same model, pretending to
fail over). Think agents therefore declare `fallback_model: none`: if Opus 4.8 `[1m]` is
unavailable, fail loud rather than silently "recover" to the identical model. Formula and
mechanical KEEP real fallbacks because they fall to *genuinely different, cheaper* tiers
(sonnet-5 → haiku; haiku → session), not no-ops.

**session = Opus 4.8 on this account**, so a formula/mechanical agent reaching
session is a **COST-INCREASE event** (an acknowledged exception to never-cross-up,
because session is the only universal floor) — log it loudly, never silently.

### Logging

Every fallback activation is logged for Loki's monthly review:
- Which agent
- Which model was unavailable
- What model was actually used
- Whether the output quality was acceptable

## Deliberate Trade: 1M-context PINNED (reversed)

Previously the `[1m]` 1M-context profiles were dropped. **That trade is now REVERSED:**
we deliberately pin the `[1m]` profiles for opus and sonnet, buying 1M context (more
room per session, less pre-dispatch chunking/summarization). Haiku stays bare (200K —
no `[1m]` variant exists). Console-read 2026-09-01 (AWS console): no `[1m]`/>200K tier
was observed — one flat rate per model regardless of context window. Re-verify if sessions
exceed 200K tokens (Anthropic first-party DOES tier >200K; Bedrock mirror unconfirmed)
(see Formula band / Fork C below).

## Cost Note

Rates (per MTok, input/output): **Opus 4.8 = $5/$25 · Sonnet 5 = $2/$10 · Haiku 4.5 =
$1/$5** · (Fable 5 = $10/$50, 2×Opus — dead/unused 4th slot). Version does NOT change
price within a tier — only the tier does (all Opus versions are the same $5/$25). Note
**Sonnet 5 ($2/$10) is CHEAPER than the old Sonnet 4.6 ($3/$15)** — the formula band got
both an upgrade and a cost cut. Real rate savings come only from dropping tier
(Opus → Sonnet → Haiku); the biggest lever of all is not making Opus agents run when a
cheaper agent (or the workflow) should — see [[loki-review]] on delegation discipline.

## Workflow agent() model overrides

Workflow stages spawned via `agent()` inherit the **main-loop model (Opus 4.8)** unless
an explicit `model:` is passed. To stop the mechanical stages from silently running on
Opus, `workflows/standard-pipeline.js` downshifts exactly three stages via a `BAND`
const (band-name → pinned id):

| Stage | Band | Pinned id |
|-------|------|-----------|
| `recall:prime` | haiku | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `gauntlet:test` | sonnet | `us.anthropic.claude-sonnet-5[1m]` |
| `hermes:ship` | haiku | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `ledger:record` | sonnet | `us.anthropic.claude-sonnet-5[1m]` |

`recall:prime` is a mechanical shell-out (run recall.sh, return stdout verbatim), so it is
downshifted to haiku in every workflow that has it (#22). Reasoning / blast-radius stages
(`scribe:recraft`, `forge:implement`, `athena:review`, `specter`, `loki`, `odin:decompose`)
are intentionally **left on the default (Opus)** — do not downshift them. Each downshifted
stage also sets `agentType` (persona) and `log()`s its intended model so the transcript
shows the tier.

**Rules:**
- Prefer the band name / `agentType` over hardcoded ids (`model: BAND.sonnet`, not a raw
  string).
- Every `model:` **string literal** under `workflows/*.js` must be one of the 3 live
  pinned ids (with the `[1m]` suffix verbatim for opus/sonnet) — enforced by
  `scripts/ci/validate.sh` (fails CI otherwise, closing the 400-on-unpinned-id door).

## Main-loop / Agent-tool spawns (#44)

When the MAIN LOOP (or any ad-hoc dispatch) spawns a specialist via the **Agent tool**, it
must pass the `model` override so mechanical/formula work does NOT inherit Opus 4.8:

| Spawn tier | agents | Agent-tool `model` |
|-----------|--------|--------------------|
| mechanical | hermes, cipher, herald | `haiku` |
| formula | gauntlet, ledger | `sonnet` |
| think | odin, muse, scribe, forge, athena, specter, loki, safecracker, titan | *(omit → inherits Opus)* |

CRITICAL: the Agent tool's `model` takes an **enum** (`haiku`/`sonnet`/`opus`/`fable`) and
the harness maps it to the pinned id. Do NOT pass a raw Bedrock id here — a raw
`sonnet-4-5[1m]` string 400'd (the finding behind #44). (Workflow `agent()` calls are the
other surface: they take a pinned-id literal via `BAND`, enforced by validate.sh.) Either
way: never an unpinned id.

Note: `haiku` and `sonnet` are now live pins, so a `haiku`/`sonnet` override cuts
**dollars immediately** (haiku → $1/$5, sonnet-5 → $2/$10) as well as context. The
enum maps to the pinned id, so no id change is needed here — the `sonnet` enum resolves
to `us.anthropic.claude-sonnet-5[1m]` via the harness.

**COVERAGE BOUNDARY:** This only covers **workflow-internal mechanical stages**. Ad-hoc
**main-loop** spawns (e.g. `general-purpose` / `Explore` subagents) still inherit
Opus 4.8 and are **NOT** fixed here — route those through the #4-family work / Cost
Directive on delegation discipline. Issue #13 is **not** "the fix for 100%-Opus."

## Bedrock Model IDs (inference-profile form)

```
opus 4.8   → us.anthropic.claude-opus-4-8[1m]
sonnet 5   → us.anthropic.claude-sonnet-5[1m]
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

## Formula-band model decision (Fork C — DECIDED)

**Sonnet 5 is the formula-band model.** Its base rate ($2/$10) clears the old $3/$15
Sonnet 4.6 ceiling — this is an upgrade AND a cost cut, so the cost-control-band
constraint is satisfied.

**Pricing console-read 2026-09-01 (AWS console): no >200K tier observed — one flat rate
per model regardless of context window.** On that reading `sonnet-5[1m]` bills at the same
$2/$10 base rate as any Sonnet 5 profile, so `cost-report.sh` applying one flat rate per
model family holds. **Re-verify if sessions exceed 200K tokens:** Anthropic's first-party
API DOES tier >200K for 1M-context models, and Bedrock is not confirmed to mirror it — a
console screenshot can miss such a row, and `[1m]` profiles exist to run >200K sessions.
The console price is the on-demand LIST upper bound; the committed-use/EDP discount is a
separate layer captured by `BEDROCK_COST_FACTOR` in `cost-report.sh`.
