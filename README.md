# Syndicate v2.0

> *"Every heist needs a crew. Every crew needs a plan. Every plan needs an Odin."*

A multi-agent orchestration system for Claude Code. Thirteen specialists, one orchestrator, zero wasted keystrokes.

**Two modes:**
- **Layered** — installs on top of [BJ's CC Workflow](https://github.com/Wave-Engineering/claudecode-workflow). Detects it automatically, layers agents on top, inherits all safety hooks.
- **Standalone** — works without BJ's workflow. Provides its own safety hooks, autonomy system, and pre-commit gates.

---

## The Crew

```
                         ┌─────────┐
                    ┌────│  ODIN   │────┐
                    │    │ (4.8)   │    │
                    │    └────┬────┘    │
                    │         │         │
              ┌─────┴──┐  ┌──┴───┐  ┌──┴─────┐
              │ SCRIBE  │  │ LOKI │  │ LEDGER │
              │ (4.7)   │  │(4.8) │  │ (4.8)  │
              └────┬────┘  └──┬───┘  └────────┘
                   │          │
        ┌──────────┼──────────┼──────────┐
        │          │          │          │
   ┌────┴───┐ ┌───┴────┐ ┌───┴───┐ ┌───┴────┐
   │ FORGE  │ │ ATHENA │ │TITAN  │ │GAUNTLET│
   │ (4.7)  │ │ (4.7)  │ │(4.7) │ │ (4.7)  │
   └────────┘ └────────┘ └───────┘ └────────┘

   ┌──────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌─────────┐
   │SAFECRACKR│  │ HERMES │  │ HERALD │  │ CIPHER │  │ SPECTER │
   │  (4.7)   │  │ (son5) │  │ (son5) │  │ (son5) │  │  (4.8)  │
   └──────────┘  └────────┘  └────────┘  └────────┘  └─────────┘
```

| Agent | Role | Tier |
|-------|------|------|
| **Odin** | Orchestrator — routes, dispatches, monitors | 1 |
| **Scribe** | Prompt Crafter — refines intent into surgical briefings | 2 |
| **Loki** | Devil's Advocate — challenges, observes, proposes improvements | 1 |
| **Ledger** | Activity Tracker — logs work as it happens, generates reports | 1 |
| **Specter** | Investigator — multi-angle diagnosis, flight recorder | 1 |
| **Forge** | Coder — writes code, nothing else | 2 |
| **Athena** | Reviewer — finds bugs at 80%+ confidence only | 2 |
| **Gauntlet** | Tester — runs tests, creates the push sentinel | 2 |
| **Hermes** | Git Ops — branches, commits, PRs via /scp | 3 |
| **Titan** | Infra — AWS/cloud, read-only by default | 2 |
| **Safecracker** | Secrets — vault ops, never plaintext | 2 |
| **Herald** | Messenger — drafts messages, never sends | 3 |
| **Cipher** | Doc Ingestion — PDF/DOCX → markdown | 3 |

---

## Autonomy — "Say Godspeed"

Syndicate has a **decaying autonomy mandate**. Instead of confirming every step:

```
You: "godspeed — implement the user profile feature"

Pipeline flows: Scribe → Forge → Gauntlet → Athena → Hermes
No confirmation prompts. Confidence decays over turns.
Checkpoints automatically when confidence drops.

You: "HALT!" — immediate stop at any time.
```

**What Godspeed NEVER overrides:**
- Production mutations (absolute rule)
- Secrets staging (gate stays armed)
- `/precheck` before commit (always runs)

See: `SYNDICATE_AXIOMS.md` for the full rule set.

---

## Pipelines — Multi-Agent Chains

Every task flows through a pipeline. Odin identifies the full chain up front.

| Trigger | Pipeline |
|---------|----------|
| "fix/implement X" | Scribe → Forge → Athena → Hermes → Ledger |
| "why is X broken" | Specter → Loki argues → Options → User picks → Forge |
| "review this" | Scribe → Athena → Ledger |
| "test this" | Scribe → Gauntlet → Ledger |
| "write + test + ship" | Scribe → Forge → Gauntlet → Athena → Hermes → Ledger |

Pipelines produce **Evidence Packets** — structured records of what happened, stored at `~/.syndicate/evidence/`.

---

## Skills

| Skill | Purpose |
|-------|---------|
| `/route` | Entry point — pass any task to Odin |
| `/status` | Generate weekly status report via Ledger |
| `/engage` | Session start — load state, check crew, confirm rules |
| `/godspeed` | Arm/disarm autonomy mandate |
| `/precheck` | Pre-commit gate (branch, secrets, review) |
| `/wtf` | Flight recorder for investigations |
| `/thoughts` | Stress-test a proposal via Loki + Specter |

In layered mode (BJ's workflow present), `/precheck` and `/wtf` defer to BJ's more comprehensive versions.

---

## Safety — The Axioms

Ten binding rules. Each earned its place through a specific failure (see `SYNDICATE_AXIOMS.md`).

The big ones:
1. **ACT, don't ASK** — mandatory procedures are executed, not proposed
2. **Human holds irreversible keys** — no prod mutation without approval
3. **Confidence decays** — unlimited autonomy produces garbage
4. **Tests unlock shipping** — no sentinel, no push
5. **Toolkit exists — use it** — don't reinvent /precheck with raw git

---

## Hooks

| Hook | Type | Purpose |
|------|------|---------|
| `pre-push-test-gate.sh` | PreToolUse | Blocks push without test sentinel |
| `pre-stage-secrets-gate.sh` | PreToolUse | Blocks staging .env/.key/.pem |
| `post-tool-test-sentinel.sh` | PostToolUse | Creates sentinel when tests pass |
| `godspeed.sh` | Stop | Decaying autonomy gate |
| `precheck-asking-detector.sh` | Stop | Blocks agents that ask instead of act |
| `post-compact-reread.sh` | PostCompact | Re-reads state after compaction |
| `session-end-ledger.sh` | SessionEnd | Logs session work to Ledger |
| `godspeed-arm.sh` | Utility | Arms the godspeed mandate |

In layered mode, BJ's hooks take priority. These are for standalone users.

---

## Installation

```bash
cd ~/Syndicate  # or wherever you cloned it
./install.sh
```

**Smart installer detects your environment:**
- BJ's CC Workflow present? → Layers on top (agents only, doesn't touch your hooks/skills/settings)
- Standalone? → Installs agents + creates settings template + registers hooks

**What gets installed:**
- `~/.claude/agents/` ← Syndicate agent definitions (symlinked)
- `~/.syndicate/` ← Ledger tracking, evidence packets, pipeline state

**Uninstall:** delete symlinks from `~/.claude/agents/` and remove `~/.syndicate/`.

---

## Toolkit Awareness

Every agent knows its environment. They know:
- Which `/skills` to invoke and when
- Which hooks will fire on their actions
- Which MCP tools are available
- How to coordinate (Gauntlet's sentinel unlocks Hermes's push)

Full reference: `config/toolkit.md`

---

## Model Tiers

| Tier | Who | Primary | Fallback | Rule |
|------|-----|---------|----------|------|
| 1 — Command | Odin, Loki, Ledger, Specter | Opus 4.8 | Opus 4.7 | Never falls to Sonnet |
| 2 — Execution | Forge, Athena, Gauntlet, Titan, Safecracker, Scribe | Opus 4.7 | Opus 4.6 | Never falls to Sonnet |
| 3 — Utility | Hermes, Herald, Cipher | Sonnet 5 | Sonnet 4 | Never falls to Haiku |

---

## Project Structure

```
Syndicate/
├── agents/              ← 13 agent definitions (symlinked to ~/.claude/agents/)
├── config/
│   ├── toolkit.md       ← full reference: skills, hooks, MCPs, decision matrix
│   ├── models.md        ← model tiers and assignments
│   ├── permissions.md   ← per-agent command reference
│   ├── evidence-packet.md ← evidence packet format
│   └── settings.template.json ← standalone settings.json
├── hooks/               ← safety hooks (standalone mode)
├── skills/              ← Syndicate-specific skills
├── scripts/
│   ├── ci/              ← validate.sh, drift-check.sh
│   ├── pipeline-state.sh ← pipeline state management
│   └── write-evidence-packet.sh ← evidence packet writer
├── loki/logs/           ← Loki's improvement observations
├── CLAUDE.md            ← project rules
├── SYNDICATE_AXIOMS.md  ← 10 binding rules + scar registry
└── README.md            ← you are here
```

---

## Roadmap

- [x] v1.0 — Agent definitions, model tiers, install script
- [x] v2.0 — Toolkit awareness, Godspeed autonomy, safety hooks, axioms, skills, pipeline persistence
- [x] v2.1 — Deterministic pipeline engine (JS workflows instead of LLM orchestration)
- [x] v2.2 — Wave pattern integration (multi-issue campaign execution)
- [ ] v3.0 — Visual UI (the Jarvis/galaxy dream)
- [ ] v3.1 — markitdown integration for Cipher

---

## Philosophy

> *"You don't hire a safecracker to drive the getaway car."*

Every agent does one thing. Odin knows who does what. The human holds the keys.
The toolkit exists — use it. Every rule is a scar. That's the whole system.

---

*Built by Jayam Patel. Powered by Claude Code. Adapted from [BJ's CC Workflow](https://github.com/Wave-Engineering/claudecode-workflow) philosophy.*
