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

| Tier | Agents | Primary | Fallback | Universal |
|------|--------|---------|----------|-----------|
| 1 — Command | Odin, Loki, Ledger, Specter | opus 4.8 | opus 4.6 | session model + warn |
| 2 — Execution | Forge, Athena, Gauntlet, Titan, Safecracker, Scribe | opus 4.7 | opus 4.6 | session model + warn |
| 3 — Utility | Hermes, Herald, Cipher | sonnet 4 | session model | — |

**Fallback rules:**
- All Opus agents → Opus 4.6 (one shared fallback, no intermediate steps)
- Sonnet agents → session model (they're already running light work)
- Universal fallback: if everything is unavailable, use session model + warn user

## Safety Guards

In layered mode, these come from BJ's `~/.claude/settings.json` hooks.
In standalone mode, these come from Syndicate's own `hooks/` directory.

Either way, agents respect:
- `stop-action-bias-detector` — gates prod/irreversible keywords
- `/precheck` — mandatory before any commit
- `pre-push-test-gate` — tests must pass before push
- `pre-stage-secrets-gate` — blocks staging credentials
- AWS `--profile` enforcement — never AWS_PROFILE= env var
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

## Evidence Packets

Every completed pipeline produces an evidence packet at `~/.syndicate/evidence/`.
- What happened, who did what, what the outcome was
- Used by Ledger (weekly reports), Loki (patterns), and Specter (past investigations)
- Audit trail: proves agents did what you asked

## Pipeline State Persistence

Active pipeline state lives at `~/.syndicate/pipelines/current.json`.
- If session dies mid-pipeline, next session can resume
- Tracks: which stage, what's done, what's next, any concerns raised
