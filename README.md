# Syndicate

> *"Every heist needs a crew. Every crew needs a plan. Every plan needs an Odin."*

A personal multi-agent orchestration system for Claude Code. Twelve specialists, one orchestrator, zero wasted keystrokes.

Syndicate doesn't replace your existing Claude Code workflow — it rides shotgun. Your safety hooks stay armed, your skills stay loaded, your CLAUDE.md stays law. Syndicate just gives you a crew to delegate to.

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

   ┌──────────┐  ┌────────┐  ┌────────┐  ┌────────┐
   │SAFECRACKR│  │ HERMES │  │ HERALD │  │ CIPHER │
   │  (4.7)   │  │ (son5) │  │ (son5) │  │ (son5) │
   └──────────┘  └────────┘  └────────┘  └────────┘
```

| Agent | Role | Vibe |
|-------|------|------|
| **Odin** | Orchestrator | The All-Father sees all, routes all. Doesn't swing the hammer — sends the one who does. |
| **Scribe** | Prompt Crafter | Translates "fix the thing" into a surgical briefing. The interpreter between you and the specialists. |
| **Loki** | Devil's Advocate | Watches the crew work and asks uncomfortable questions. Keeps a monthly burn book of everything that could be sharper. Self-learning, never self-applying. |
| **Ledger** | Activity Tracker | The bookkeeper who never sleeps. Logs your work as it happens. Come Wednesday, your status report writes itself. |
| **Specter** | Investigator | The ghost that phases through your systems and finds what's lurking. Attacks from every angle, argues with Loki, presents options A/B/C/D. Read-only until you say otherwise. |
| **Forge** | Coder | Hammer meets anvil. Writes code, matches patterns, reports what it built. No gold-plating, no unsolicited abstractions. |
| **Athena** | Reviewer | Wisdom over speed. Finds the bug you'd ship to prod. Only speaks when she's 80%+ confident — no style nitpicks, no noise. |
| **Gauntlet** | Tester | The trial by fire. Runs your tests, writes new ones, stress-tests the edges. If it passes Gauntlet, it ships. |
| **Hermes** | Git Ops | The messenger god. Branches, commits, PRs — moved between worlds before you finish your coffee. |
| **Titan** | Infra | Atlas, but for AWS. Holds up the cloud. Default: read-only. Mutating? Better believe he's asking permission first. |
| **Safecracker** | Secrets | Cracks vaults open, never leaves a trace. Your keys, credentials, and rotation policies — handled with gloves. |
| **Herald** | Messenger | Drafts your Teams messages and emails. Professional but not robotic. Copy-paste and send. |
| **Cipher** | Doc Ingestion | Turns your PDFs and DOCX files into markdown faster than you can say "markitdown." |

---

## Model Tiers — "Not Everyone Gets the Big Gun"

Every agent gets a model matched to their cognitive load. Fallbacks stay in-family — an Opus agent never degrades to Sonnet. That's not a fallback, that's a demotion.

| Tier | Who | Primary | Fallback | Why |
|------|-----|---------|----------|-----|
| **1 — Command** | Odin, Loki, Ledger, Specter | Opus 4.8 | Opus 4.7 | These agents *think*. Routing, arguing, tracking, investigating — all require top-tier reasoning. |
| **2 — Execution** | Forge, Athena, Gauntlet, Titan, Safecracker, Scribe | Opus 4.7 | Opus 4.6 | These agents *do*. Code, review, test, infra — precision matters. |
| **3 — Utility** | Hermes, Herald, Cipher | Sonnet 5 | Sonnet 4 | These agents *move things*. Git commands, message formatting, file conversion — formulaic, fast. |

---

## The Flow — "How a Heist Goes Down"

```
 You: "fix the headscale coppermind path issue"
  │
  ▼
 ODIN classifies → infra + code → needs Forge + Titan context
  │
  ▼
 SCRIBE recrafts → adds repo path, container ID, "read-only first" constraint
  │
  ▼
 FORGE executes → edits compose.yml, adds COPPERMIND_PATH env var
  │
  ▼
 LOKI observes → "did you check if the entrypoint reads this var at startup?"
  │
  ▼
 ODIN reports back → "Done. Forge edited services/rumrunner/compose.yml. Loki flagged
                       a follow-up: verify the entrypoint var consumption. Route to Gauntlet?"
  │
  ▼
 You: "yes" or "nah, ship it"
```

**Human in the loop.** Always. Odin shows you where it's routing and why. You redirect or confirm. The existing safety hooks (`/precheck`, stop-action-detector, prod gates) enforce the hard stops — Syndicate doesn't need to re-implement them because it *runs inside* the same Claude Code session.

---

## Ledger — "The Books Never Lie"

Ledger tracks your work **as it happens**. No more "wait, what did I do this week?" on Wednesday afternoon.

- **Live mode**: logs every commit, MR, investigation as you work
- **"Don't track this"**: removes the entry, no questions asked
- **Weekly**: generates your manager's status report (Wednesday COB rotation)
- **Monthly**: summarizes for Loki's improvement cycle

Weekly format (your manager's template — ready to paste into Word):
```
• Accomplishments since last week:
    ○ Rumrunner VPN infrastructure — multi-repo fix:
        ■ Built headscale bootstrap entrypoint (blueshift-rumrunner #7, merged)
        ■ Fixed COPPERMIND_PATH env var (blueshift-manifests #483, merged)
    ○ NSS self-service tooling:
        ■ Implemented nss_cluster_list (blueshift-ansible #142, merged)
• Blockers, and whether or not there is a mitigation:
    ○ BJ out — parked items needing review. Mitigation: documentation work.
• Are you on track, behind, or ahead?
    ○ On track. 10 merged MRs across 4 repos.
```

---

## Loki — "The Self-Sharpening Blade"

Loki does two things:

1. **Real-time**: argues with Forge, Athena, Gauntlet, and Titan while they work. Not for the sake of arguing — only when he has a concrete alternative or a blind spot to expose.

2. **Monthly**: reviews his log of observations, spots patterns, and proposes improvements to agent definitions. Proposals are *presented*, never auto-applied. You approve, then he routes the changes to Forge.

> *"A crew that never questions itself is a crew about to get caught."*

---

## Installation

```bash
cd ~/Syndicate
./install.sh
```

**What gets installed:**
- `~/.claude/agents/` ← agent definitions (symlinked back here)
- `~/.syndicate/ledger/` ← live tracking data

**What does NOT get touched:**
- `~/.claude/skills/` ← your /engage, /precheck, /scp — untouched
- `~/.claude/settings.json` ← your hooks, permissions — untouched
- Any project `CLAUDE.md` — untouched

The install is non-destructive and reversible. To uninstall: delete the symlinks from `~/.claude/agents/`.

---

## Coexistence — "Two Bosses, One Desk"

Syndicate sits *alongside* BJ's workflow, not on top of it. Think of it as:

- **BJ's workflow** = the security system (locks, cameras, alarms)
- **Syndicate** = the crew (specialists who work *within* the secured building)

The hooks still fire. `/precheck` still gates commits. The prod rule is still absolute. Syndicate agents inherit all of that because they execute inside Claude Code sessions where those rules are loaded.

---

## Roadmap

- [x] v1.0 — Agent definitions, model tiers, install script
- [ ] v1.1 — Ledger live-tracking hook (SessionEnd auto-log)
- [ ] v1.2 — Loki monthly report generation
- [ ] v2.0 — Visual UI (the Jarvis/galaxy dream)
- [ ] v2.1 — markitdown integration for Cipher
- [ ] v3.0 — Inter-agent communication protocol

---

## Philosophy

> *"You don't hire a safecracker to drive the getaway car."*

Every agent does one thing. Odin knows who does what. The human holds the keys. That's the whole system.

---

*Built by Jayam Patel. Powered by Claude Code. Inspired by heists, mythology, and the belief that your AI should work as hard as you do.*
