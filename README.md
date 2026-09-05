# Syndicate v2.0

> *"Every heist needs a crew. Every crew needs a plan. Every plan needs an Odin."*

A multi-agent orchestration system for Claude Code. Thirteen specialists, one orchestrator, zero wasted keystrokes. (Odin routes; the crew executes.)

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
| **Muse** | Conception Partner — shapes fuzzy ideas into designed intent | 1 |
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

Pipelines are recorded in the **Ledger** (`~/.syndicate/ledger/current-week.md`) — a running log of what happened, fed automatically by the SessionEnd hook.

---

## Skills

**The flow:** `/engage` → `/syndicate` → then just talk. After `/syndicate`, every
message auto-routes through Odin — no `/route` prefix needed.

| Skill | Purpose |
|-------|---------|
| `/syndicate` | **Activate self-dispatch** (run after /engage) — then just talk |
| `/route` | Manually route one task through Odin (if not self-dispatching) |
| `/recall` | Pull relevant recent sessions + repo merge history |
| `/muse` | Conception — shape a fuzzy idea before building |
| `/campaign` | Multi-issue wave execution |
| `/goalseek` | Open-ended probe→judge→steer loop |
| `/godspeed` | Arm/disarm autonomy mandate |
| `/status` | Generate weekly status report via Ledger |
| `/engage` | Session start — load state, check crew, confirm rules |
| `/precheck` | Pre-commit gate (branch, secrets, review) |
| `/wtf` | Flight recorder for investigations |
| `/thoughts` | Stress-test a proposal via Loki + Specter |

In layered mode (BJ's workflow present), `/engage`, `/precheck`, `/wtf`, and
`/thoughts` defer to BJ's versions; `/syndicate` layers routing on top of them.

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
| `pre-push-test-gate.sh` | PreToolUse | Blocks push without a fresh per-worktree test sentinel |
| `pre-stage-secrets-gate.sh` | PreToolUse | Blocks staging .env/.key/.pem |
| `post-tool-test-sentinel.sh` | PostToolUse | Creates the per-worktree sentinel when tests pass |
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
- `~/.syndicate/` ← Ledger tracking, pipeline state

**Uninstall:** run `./uninstall.sh`. It's fully reversible and surgical:
- Removes only Syndicate's agent/skill symlinks (yours and BJ's are untouched)
- Strips only Syndicate's hook entries from `settings.json` (backs it up first;
  BJ's hooks and your own are preserved)
- **Keeps your data by default** — ledger, conception ledgers
- **Never touches** your session history in `~/.claude/projects/`
- `./uninstall.sh --purge` also removes `~/.syndicate/` data (asks first)

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

Model is chosen by **role, not rank** — think-work gets Opus, formula-work gets Sonnet/Haiku:

| Model | Agents | Why |
|-------|--------|-----|
| **Opus 4.8** | Odin, Muse, Loki, Specter | Orchestrate / conceive / attack / investigate — pure reasoning |
| **Opus 4.7** | Athena | Reason about bugs at 80%+ confidence |
| **Opus 4.6** | Forge, Scribe, Titan, Safecracker | Blast-radius: code/infra/secrets — a weak model's mistake is costly |
| **Sonnet 4.6** | Gauntlet, Ledger | Running tests + formatting reports — mostly mechanical |
| **Haiku 4.5** | Hermes, Herald, Cipher | Git commands / message templates / file conversion — pure formula |

**Cost reality:** all Opus versions are the same rate ($5/$25). 4.6-vs-4.8 is a capability choice, not a cost cut. Real savings are Opus→Sonnet (−40%) and Sonnet→Haiku (−80%) — and the biggest lever is not running Opus agents when the workflow or a cheaper agent should do the work.

**Fallback:** each agent falls back within its family or to the session model (never up a tier). If everything's unavailable, it uses whatever model your Claude Code session runs, with a warning.

---

## Project Structure

```
Syndicate/
├── agents/              ← 13 agent definitions (symlinked to ~/.claude/agents/)
├── config/
│   ├── toolkit.md       ← full reference: skills, hooks, MCPs, decision matrix
│   ├── models.md        ← model tiers and assignments
│   ├── permissions.md   ← per-agent command reference
│   ├── model-audit.md   ← SessionEnd model-drift audit spec
│   └── settings.template.json ← standalone settings.json
├── hooks/               ← safety hooks (standalone mode)
├── skills/              ← Syndicate-specific skills
├── scripts/
│   ├── ci/              ← validate.sh, drift-check.sh
│   └── pipeline-state.sh ← pipeline state management
├── loki/logs/.gitkeep   ← Loki's repo footprint (logs + regenerable CHANGELOG stay local in ~/.syndicate/loki/, gitignored)
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
