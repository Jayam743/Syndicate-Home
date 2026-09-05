# Syndicate — Project Rules

This is the Syndicate multi-agent orchestration system. It works in TWO modes:
1. **Layered** — installs on top of BJ's CC Workflow (detected automatically)
2. **Standalone** — provides its own hooks, safety gates, and permissions

## Coexistence with BJ's Workflow

When BJ's workflow is detected (`~/.claude/skills/engage/SKILL.md` exists):
- Syndicate installs into `~/.claude/agents/` only
- Does NOT touch: `~/.claude/skills/`, `~/.claude/settings.json`, any project CLAUDE.md
- BJ's safety stack remains the enforcement layer
- Syndicate agents inherit those rules (they run INSIDE the same CC session)

When standalone (BJ's workflow NOT detected):
- Syndicate installs agents, hooks, and a settings.json template
- Provides its own safety gates (pre-push-test-gate, pre-stage-secrets, stop-action-bias-detector)
- The safety philosophy is the same, just self-provided

## Architecture

Odin is the orchestrator. All tasks flow through him. He recrafts prompts via Scribe,
then routes to specialists. Loki watches critical agents and argues.

## Human in the Loop

**Syndicate never acts autonomously on irreversible operations.** The flow is:

1. You give a task (natural language)
2. Odin classifies and shows you: "Routing to [Agent] with this prompt: [refined prompt]"
3. You confirm or redirect (or say "godspeed" to skip confirmations)
4. Agent executes (with hooks as guardrails)
5. Odin + Loki observe the lifecycle
6. Result comes back to you

**Godspeed mode**: say "godspeed" to arm the autonomy mandate.
Pipeline flows without per-step confirmation. Decays over turns.
"HALT!" revokes immediately.

**What Godspeed NEVER overrides:**
- Prod mutations (absolute rule)
- Secrets staging (gate stays armed)
- Precheck before commit (always runs)

## Toolkit Awareness

Agents know their environment. They know:
- Which /skills to invoke and when (see `config/toolkit.md`)
- Which hooks will fire on their actions
- Which MCP tools are available via ToolSearch
- When to use Godspeed flow vs manual gates
- How to coordinate (Gauntlet's test sentinel unlocks Hermes's push)

**Agents ACT, they don't ASK.** Hermes runs `/precheck` — doesn't ask "shall I run precheck?"

## Agent Definitions

Agent markdown files live in `agents/`. Each file defines:
- Frontmatter: name, model, fallback_model, tier, description, tools
- System prompt: personality, rules, output format
- Toolkit awareness section: what skills/hooks/MCPs to use and when

## Model Tiers

3-band model on **subscription aliases** (full rationale in `config/models.md`):

| Band | Alias | Agents |
|------|-------|--------|
| think | `opus` | Odin, Muse, Loki, Scribe, Specter, Athena |
| formula | `sonnet` | Forge, Gauntlet, Ledger, Titan, Safecracker |
| mechanical | `haiku` | Hermes, Herald, Cipher |

Athena runs a conditional cross-family second pass on `sonnet` for high-stakes/security
diffs (review-diversity) — a review-workflow behavior, not a frontmatter fallback.

**Fallback rules:**
- Every agent declares `fallback_model: none`. Subscriptions resolve the alias directly;
  there is no honest cheaper-tier failover and no `session` no-op (the session IS the
  resolved model). If an alias fails to resolve, fail loud.
- Quota, not dollars, is the scarce resource: keep the think band lean and delegate
  formulated work to Sonnet (see the Quota Directive in `config/doctrine.md`).

## Safety Guards

In layered mode, these come from BJ's `~/.claude/settings.json` hooks.
In standalone mode, these come from Syndicate's own `hooks/` directory.

Either way, agents respect:
- `stop-action-bias-detector` — gates prod/irreversible keywords
- `/precheck` — mandatory before any commit
- `pre-push-test-gate` — tests must pass before push
- `pre-stage-secrets-gate` — blocks staging credentials
- Closed legal exits — only 3 reasons to halt a pipeline

## Development Rules

- Edit agents here in the Syndicate repo, not in `~/.claude/agents/` (symlinks point back)
- Test changes by running Claude Code in this directory
- Version bumps: update README.md version line
- Keep agent definitions focused — one job per agent
- Run `./scripts/ci/validate.sh` before pushing
- Run `./scripts/ci/drift-check.sh` to verify install state

## Ledger: Live Tracking

Ledger tracks work in real-time to `~/.syndicate/ledger/current-week.md`.
- Tracks by default (silence = keep logging)
- "Don't track this" = remove the entry
- Weekly rotation: Wednesday COB
- Monthly rollup for Loki's improvement cycle

## Work Record

The honest record of what happened lives in the Ledger
(`~/.syndicate/ledger/current-week.md`), fed automatically by the SessionEnd hook.
A companion SessionEnd audit writes `~/.syndicate/ledger/model-audit.md` — one row per
subagent proving it ran on its intended model (see `config/model-audit.md`).

## Pipeline State Persistence

Active pipeline state lives at `~/.syndicate/pipelines/current.json`.
- If session dies mid-pipeline, next session can resume
- Tracks: which stage, what's done, what's next, any concerns raised
