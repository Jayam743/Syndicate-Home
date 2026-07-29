# Syndicate — Project Rules

This is the Syndicate multi-agent orchestration system. It LAYERS on top of BJ's existing
Claude Code workflow — it does NOT replace it.

## Coexistence with BJ's Workflow

Syndicate installs into `~/.claude/agents/` only. It does NOT touch:
- `~/.claude/skills/` (engage, precheck, scp, etc. — all stay)
- `~/.claude/settings.json` (hooks, permissions — all stay)
- Any project's `CLAUDE.md` (safety rules — all stay)
- The stop hooks (godspeed, prod-guard — all stay)

BJ's safety stack remains the enforcement layer. Syndicate agents inherit those rules
because they run INSIDE Claude Code sessions where those hooks are active.

## Architecture

Odin is the orchestrator. All tasks flow through him. He recrafts prompts via Scribe,
then routes to specialists. Loki watches the critical agents and argues.

## Human in the Loop

**Syndicate never acts autonomously on irreversible operations.** The flow is:

1. You give a task (natural language)
2. Odin classifies and shows you: "Routing to [Agent] with this prompt: [refined prompt]"
3. You confirm or redirect
4. Agent executes (with BJ's hooks as guardrails)
5. Odin + Loki observe the lifecycle
6. Result comes back to you

For trivial/safe tasks (read-only, drafting messages), step 3 is implicit.
For anything touching prod/secrets/infra, the existing hooks enforce the gate.

## Agent Definitions

Agent markdown files live in `agents/`. Each file defines:
- Frontmatter: name, model, fallback_model, tier, description, tools
- System prompt: personality, rules, output format

## Model Tiers

| Tier | Agents | Primary | Fallback |
|------|--------|---------|----------|
| 1 — Command | Odin, Loki, Ledger | opus 4.8 | opus 4.7 |
| 2 — Execution | Forge, Athena, Gauntlet, Titan, Safecracker, Scribe | opus 4.7 | opus 4.6 |
| 3 — Utility | Hermes, Herald, Cipher | sonnet 5 | sonnet 4 |

**Fallback rule:** same family only. Opus never falls to sonnet. Sonnet never falls to haiku.

## Safety Guards (inherited from BJ's workflow)

These are NOT re-implemented — they come from the existing `~/.claude/settings.json` hooks:
- `stop-action-bias-detector.sh` — gates prod/irreversible keywords
- `/precheck` — mandatory before any commit
- CLAUDE.md ABSOLUTE rules — no touching user's Portainer, no prod without approval
- AWS `--profile` enforcement — never use AWS_PROFILE= env var

Syndicate agents must respect all of these. They run in the same session = same rules.

## Development Rules

- Edit agents here in the Syndicate repo, not in `~/.claude/agents/` (symlinks point back)
- Test changes by running Claude Code in this directory
- Version bumps: update README.md version line
- Keep agent definitions focused — one job per agent

## Ledger: Live Tracking

Ledger tracks work in real-time to `~/.syndicate/ledger/current-week.md`.
- Tracks by default (silence = keep logging)
- "Don't track this" = remove the entry
- Weekly rotation: Wednesday COB
- Monthly rollup for Loki's improvement cycle
