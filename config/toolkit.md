# Syndicate Toolkit Reference

> This file tells agents what tools are available in their environment.
> Agents should consult this to know WHEN to invoke skills, WHAT hooks will fire,
> WHICH MCP tools exist, and WHICH deterministic workflows to execute.

## Deterministic Workflows (invoke with Workflow tool)

Workflows are coded JS pipelines. The control flow is deterministic — LLMs handle content,
scripts handle routing. Use these for multi-step work instead of manual agent chaining.

| Workflow | When | What It Does |
|----------|------|-------------|
| `syndicate-pipeline` | Code changes (implement, fix, refactor) | Scribe → Forge → Gauntlet+Athena (parallel) → Hermes → Ledger |
| `syndicate-investigation` | Unknown problems ("why is X broken?") | Specter investigates → Loki challenges → present options |
| `syndicate-review` | Code review | Two tracks: Athena bug-finding (4 dims) + omission-verification (checklist from acceptance criteria → closed per-item lookups) → Loki adversarial verify |
| `syndicate-campaign` | Multi-issue work (4+ items), KNOWN plan | Decompose into waves → execute (serial default, fan when safe) → barrier |
| `syndicate-goalseek` | Open-ended: goal clear, plan NOT known | probe → judge sufficiency → steer → journal, until sufficient or escalation |

### When to Use Workflows vs Direct Routing

| Situation | Use |
|-----------|-----|
| Multi-step code task (implement + test + review + ship) | `syndicate-pipeline` workflow |
| Something is broken, cause unknown | `syndicate-investigation` workflow |
| Review code changes | `syndicate-review` workflow |
| 4+ related issues to implement (known list) | `syndicate-campaign` workflow |
| Goal is clear but steps are unknown (research, "figure out X") | `syndicate-goalseek` workflow |
| Single-agent task (just draft a message) | Direct route to agent (no workflow) |
| Trivial task (rename a file, check a value) | Direct route to agent (no workflow) |

### Workflow Args Pattern

```javascript
Workflow({
  name: 'syndicate-pipeline',
  args: {
    task: "what the user asked for",
    context: "file paths, branch, constraints",
    skipScribe: false,  // true for obvious tasks
    skipTests: false    // true for docs-only changes
  }
})
```

## Skills (invoke with /skill or Skill tool)

Skills are packaged instructions. When you recognize a matching situation, USE the skill
rather than ad-hoccing it. The skill has the tested, refined procedure.

| Skill | When to Use | Who Typically Invokes |
|-------|-------------|----------------------|
| `/syndicate` | ACTIVATE self-dispatch (run after /engage) — after this, just talk and it routes through Odin | You (entry point) |
| `/recall` | Pull 2-3 relevant recent sessions + repo merge history before troubleshooting/building | Odin (auto for investigate/goal-seek/code-change/review) |
| `/retro` | Session retrospective — run at END; audits tokens/models/crew/mistakes for THIS session | You (end of session) |
| `/muse` | Conception — shape a fuzzy idea into designed intent before building | Odin (routes to Muse) |
| `/engage` | Session start — read CLAUDE.md, confirm rules, load plan | Odin (auto on session start) |
| `/precheck` | Before ANY commit — branch/issue validation, review, checklist | Hermes (mandatory gate) |
| `/scp` | Stage + commit + push in one flow | Hermes |
| `/scpmr` | Stage + commit + push + create PR/MR | Hermes |
| `/scpmmr` | Full pipeline: stage → commit → push → PR → merge | Hermes (small tasks only) |
| `/mmr` | Merge an existing PR/MR (squash + delete branch) | Hermes |
| `/review` | Code review via subagent | Athena |
| `/reseed` | Context window getting low — write seed, clear, revive | Odin (when context > 80%) |
| `/nerf` | Monitor/manage context budget actively | Odin |
| `/wtf` | Start incident troubleshooting flight recorder | Specter |
| `/wtf-now` | Record a manual journal entry during troubleshooting | Specter |
| `/wtf-happened` | Get incident timeline + generate runbook | Specter |
| `/issue` | Create structured issues (plan, epic, feature, story, bug, chore) | Odin / Hermes |
| `/ddd` | Domain-Driven Design — event storming, modeling, handoff | Scribe / Odin |
| `/devspec` | Create Development Specification (deliverables manifest) | Scribe / Odin |
| `/assesswaves` | Assess if work justifies wave-pattern execution (4+ issues?) | Odin |
| `/campaign` | Multi-issue wave execution — decompose + execute in waves | Odin |
| `/goalseek` | Open-ended goal-seeking — probe/judge/steer/journal loop | Odin |
| `/prepwaves` | Validate specs, compute dependency waves (BJ's workflow) | Odin |
| `/nextwave` | Execute one wave with per-wave approval (BJ's workflow) | Odin |
| `/wavemachine` | Full autonomous campaign, no per-wave gate (BJ's workflow) | Odin (godspeed mode) |
| `/wave` | Show current wave status | Ledger / Odin |
| `/thoughts` | Stress-test a proposal before acting | Loki |
| `/multithread` | Parallel discussion over independent items | Odin |
| `/grunt` | Spawn scoped-ops agent for bounded backlogs | Odin |
| `/lazyriver` | Goal-seek loop (probe → judge → steer → journal) | Specter |
| `/disc` | Discord integration (send/read/manage) | Herald |
| `/ping` / `/pong` | Inter-agent messaging | Any |
| `/vox` | Text-to-speech announcements | Herald |
| `/jfail` | Analyze failed CI job | Gauntlet |
| `/ibm` | Verify Issue → Branch → PR workflow compliance | Hermes |
| `/dod` | Definition of Done verification | Gauntlet / Odin |
| `/man` | Show usage for any skill | Any |

## Hooks (fire automatically — agents don't invoke these, but must KNOW they exist)

Hooks fire based on lifecycle events. Agents should expect their behavior.

### PreToolUse (fires before tool execution)

| Hook | What It Does | Agent Impact |
|------|-------------|--------------|
| `pre-push-test-gate.sh` | Blocks `git push` unless tests ran (sentinel file) | Gauntlet MUST run tests before Hermes pushes |
| `pre-stage-secrets-gate.sh` | Blocks `git add` of `.env`, `.key`, `.pem`, credentials | Hermes/Forge can't accidentally stage secrets |

### PostToolUse (fires after tool execution)

| Hook | What It Does | Agent Impact |
|------|-------------|--------------|
| `post-tool-test-sentinel.sh` | Creates sentinel when tests pass | Gauntlet's test runs unlock Hermes's push |
| `post-tool-context-tracker.sh` | Tracks Skill/ToolSearch invocations | Context awareness for nerf budget |

### Stop Hooks (can BLOCK the agent mid-action)

| Hook | What It Does | Agent Impact |
|------|-------------|--------------|
| `stop-action-bias-detector.sh` | **Godspeed model** — gates irreversible/prod actions. Decaying mandate: confidence must exceed bar. | ALL agents: prod/deploy/delete keywords trigger a gate. User must approve. |
| `precheck-asking-detector.sh` | Blocks agents that ASK to run precheck instead of RUNNING it | Hermes: just run `/precheck`, don't ask permission |
| `wavemachine-stall-guard` | Prevents campaign from stalling between waves | Odin: when in campaign, keep moving |

### SessionStart

| Hook | What It Does | Agent Impact |
|------|-------------|--------------|
| `reseed-revive.sh` | After `/clear`, auto-revives from seed file | Odin: state is preserved across compactions |
| `context-freshness-warn.sh` | Warns if context predates last kit install | Odin: re-read toolkit if warned |

### SessionEnd

| Hook | What It Does | Agent Impact |
|------|-------------|--------------|
| `session-end-ledger.sh` | Logs session commits to Ledger | Ledger: data arrives automatically |

**Token accounting is harness-sourced, never model-sourced.** The model cannot see
its own token meter. Ledger's token/cost figures come from `/cost` or the SessionEnd
hook — never from the model "reporting" a number. If asked for session token totals,
the honest answer is "run `/cost`", not an estimate. (This is why `/retro`'s token
section defers to `/cost` instead of guessing.)

## MCP Servers (invoke via ToolSearch → then call the tool)

MCP tools are available via `ToolSearch`. Load them on demand.

| Server | Tools Prefix | When to Use |
|--------|-------------|-------------|
| **sdlc-server** | `mcp__sdlc-server__*` | Wave management, PR/MR lifecycle, CI status, issue tracking, branch guard, commutativity checks |
| **wtf-server** | `mcp__wtf-server__*` | Flight recorder — `wtf_freshell` (start), `wtf_now` (journal), `wtf_happened` (timeline), `wtf_imout` (suspend) |
| **nerf-server** | `mcp__nerf-server__*` | Context budget — `nerf_budget`, `nerf_darts`, `nerf_mode`, `nerf_scope`, `nerf_status` |
| **disc-server** | `mcp__disc-server__*` | Discord — `disc_send`, `disc_read`, `disc_list`, `disc_create_channel`, `disc_create_thread`, `disc_resolve` |

### Key MCP Patterns

**Before pushing (Hermes):**
```
ToolSearch("select:mcp__sdlc-server__branch_guard") → call branch_guard
```

**During investigation (Specter):**
```
ToolSearch("select:mcp__wtf-server__wtf_freshell") → start flight recorder
ToolSearch("select:mcp__wtf-server__wtf_now") → journal findings
```

**Managing context (Odin):**
```
ToolSearch("select:mcp__nerf-server__nerf_status") → check budget
ToolSearch("select:mcp__nerf-server__nerf_mode") → set mode if low
```

**Wave execution (Odin):**
```
ToolSearch("select:mcp__sdlc-server__wave_show") → current status
ToolSearch("select:mcp__sdlc-server__wave_next_pending") → what's next
ToolSearch("select:mcp__sdlc-server__pr_create") → create PR
```

## Autonomy: The Godspeed Model

When the user says **"godspeed"**, it arms a decaying autonomy mandate:
- Agents operate without per-step confirmation
- Confidence decays over turns: `bar = d/N` where d = turns since godspeed, N = total expected
- When confidence drops below threshold → checkpoint (ask user)
- **"HALT!"** → immediately revoke mandate, stop all work, report status

**What Godspeed DOES NOT override:**
- The ABSOLUTE prod rule (never touch prod without approval)
- The secrets gate (never stage credentials)
- The precheck gate (always run before commit)

**Pipeline behavior under Godspeed:**
- Scribe → Forge → Athena → Hermes flows without human gates
- Specter still presents options (investigation needs human judgment)
- Loki challenges are logged as concerns, don't block

## Platform Detection

Agents should detect the git platform from remote URL:
- `github.com` → use `gh` CLI
- `gitlab.com` or internal GitLab → use `glab` CLI

Check: `git remote get-url origin 2>/dev/null`

## Available CLIs (pre-approved in permissions)

| CLI | Available | Use For |
|-----|-----------|---------|
| `gh` | GitHub | PRs, issues, releases |
| `glab` | GitLab | MRs, issues, pipelines |
| `aws` | AWS (always with --profile) | Cloud resources |
| `terraform` | IaC | Infrastructure |
| `docker` | Containers | Build, run, inspect |
| `markitdown` | Document conversion | PDF/DOCX → markdown |
| `shellcheck` | Shell linting | Validate scripts |

## Decision Matrix: When to Use What

| Situation | Use |
|-----------|-----|
| Need to commit code | `/scp` or `/scpmr` (never raw git commands) |
| Before committing | `/precheck` (mandatory, don't ask) |
| Tests must pass first | Run Gauntlet → sentinel created → then push |
| Investigating a failure | `/wtf` to start, then Specter protocol |
| Context running low | `/reseed` or `/nerf` to manage |
| Multi-issue work (4+ items) | `/assesswaves` → `/prepwaves` → `/nextwave` |
| Need to verify workflow compliance | `/ibm` (issue-branch-MR check) |
| Creating a new issue | `/issue` (structured, labeled, wave-ready) |
| Want autonomous execution | Say "godspeed" → pipeline flows without gates |
| Want to stop autonomous | Say "HALT!" → immediate stop |
