# Home Lean Port — Build Spec (branch: `home/lean-pro`)

> Bake-once spec. Build straight from this. If it proves insufficient mid-build,
> return to Odin for a spec revision — do NOT improvise wiring/model decisions.

## Goal

Produce a lean, portable variant of Syndicate for the operator's **home machine** on
the **Anthropic $20 Pro subscription** (claude.ai login — NOT Bedrock, NOT API key).
It must still behave as "BJ's CC workflow + Syndicate layered on top," using a **frozen
snapshot** of BJ's workflow vendored into this branch (BJ's live upstream has since been
containerized; do NOT fetch from it). The operator checks out this branch on the home
laptop, points Claude Code at it, and installs.

## Hard non-goals / fences (do not cross)

- **NOTHING about "blueshift." Completely unrelated to Analogic or any of its products.**
  Do not introduce, reference, or scaffold anything from that domain anywhere.
- Do **NOT** fetch/sync from BJ's live upstream repo — vendor the frozen local copy only.
- Do **NOT** re-pin to Bedrock ids or assume AWS/Bedrock. Subscriptions use **aliases**.
- Do **NOT** vendor secrets, caches, or transcripts (see §6 hard-exclusions).
- Do **NOT** build the usage/quota bar here — that is a separate phase-2 feature.
- No new features beyond what this spec lists. Keep it genuinely smaller.

---

## §1. Model re-pin — Bedrock ids → subscription aliases

Subscriptions accept only aliases (`opus`/`sonnet`/`haiku`), never full/Bedrock ids.
Re-pin the tier bands to the operator's intent (**Opus thinks/decides, Sonnet does
formulated work, Haiku mechanical**):

| Band | Alias | Agents |
|------|-------|--------|
| think | `opus` | odin, muse, loki, scribe, specter, athena |
| formula | `sonnet` | **forge**, gauntlet, ledger, titan, safecracker |
| mechanical | `haiku` | hermes, herald, cipher |

**Note the change vs current:** `forge`, `titan`, `safecracker` move from `opus` →
`sonnet` (formulated execution from a decided spec — matches operator intent AND
conserves scarce Opus quota on a subscription).

Apply the alias re-pin to EVERY model-pin site (exact set from recon):

- **All 14 `agents/*.md`** frontmatter: `model:` → the band alias above; `fallback_model:`
  → drop the Bedrock fallback ids. Set `fallback_model: none` for `opus`/`sonnet` bands;
  for `haiku` band set `fallback_model: none` too (no `session` no-op). Remove any `[1m]`.
- `agents/athena.md` prose second-pass pins (lines ~61,63,65): primary `opus`,
  cross-family second-pass `sonnet`. Keep the two-pass *behavior*, alias-only.
- **`config/models.md`** — rewrite the band→id map (lines ~11-13), delete the "[1m] is
  load-bearing" rule (~18-21) and the entire "Bedrock Model IDs (inference-profile form)"
  section (~189-218) INCLUDING the `aws bedrock list-inference-profiles` verification and
  `[1m]` pricing/tier reasoning. Replace with a short "Subscription aliases (home)" section:
  the 3 aliases, the tier table above, and one line noting full/Bedrock ids do not work on
  a subscription. Update the workflow-stage pinned table (~143-146) to aliases.
- **`CLAUDE.md`** tier-band table + fallback rules (~59,69-77) → aliases + the new tiering;
  drop the Bedrock/`[1m]`/cost-rate prose.
- **`config/doctrine.md`** Cost Directive (see §2 — largely removed).
- **`workflows/*.js`** — replace every `'us.anthropic.claude...'` literal with the alias
  the stage should use (recall:prime/hermes:ship → `haiku`; gauntlet:test/ledger:record →
  `sonnet`). `validate.sh` scans workflow literals against the pinned set, so all must match.
- **`scripts/ci/validate.sh`** `PINNED_MODELS=(...)` (~90-94) → the 3 aliases
  (`opus`/`sonnet`/`haiku`). Update the workflow-literal pinned-set check (~213-244) accordingly.
- **Test fixtures:** `scripts/ci/test-model-allowlist.sh`, `scripts/ci/test-cost-report.sh`
  (~75-93) — swap Bedrock-id fixtures for the aliases.
- **`hooks/session-end-model-audit.sh`** `norm()` (~58-63,85): simplify — aliases need no
  `us.anthropic.claude-`/`-vN`/`-YYYYMMDD`/`[1m]` stripping. Keep the audit comparing
  frontmatter alias vs runtime model family, but drop Bedrock normalization.

**Install-time verification hook (README, not code):** the home box must confirm whether
Pro grants Opus. Add to the branch README a post-install step: run `/model` and `/usage`,
and set `model: opus` on one agent to confirm it resolves (not errors). If Pro rejects
Opus, the operator flips the think band to `sonnet` (one-line, documented). Aliases make
this safe either way.

---

## §2. Strip infra prose/permissions (the "lean" pass)

All of Ceph/OpenBao/AWS/Docker/GitLab/LiteLLM are SOFT (prose/permission/gate-regex) —
no code depends on them. Remove them so the setup reads and installs lean:

- **`config/settings.template.json`**: drop permission grants `Bash(aws --profile *)`,
  `Bash(docker compose*)`, and the `terraform plan` grant. Keep `gh`; **drop `glab`**
  (home is GitHub-only). Keep git/find/grep/python/pip/npm/curl/shellcheck/markitdown.
- **`config/permissions.md`**: remove aws/vault/docker/terraform allowed-command rows.
- **`agents/titan.md`**: retarget from AWS/Terraform/Docker infra → **local dev/system ops**
  (local processes, git, filesystem). Remove `--profile`, Bedrock, cloud remit.
- **`agents/safecracker.md`**: retarget from OpenBao/Vault/AWS-SM → **local secret hygiene**
  (`.env`, `.gitignore`, `gh secret`). Remove vault/cloud remit.
- **`agents/hermes.md`**: remove GitLab/`glab`/MR paths; GitHub/`gh`/PR only.
- **`agents/odin.md`, `agents/scribe.md`, `config/toolkit.md`, `config/doctrine.md`**:
  remove AWS `--profile` enforcement doctrine, glab/MR routing, docker/aws/gitlab rows,
  Ceph/OpenBao/LiteLLM mentions. `recall.sh` glab branch (~166-185): drop the glab path,
  keep the local-git-merge-log fallback as the only path.
- **`hooks/godspeed.sh`** ABSOLUTE_GATES + **`hooks/pre-dispatch-godspeed-gate.sh`**
  MUTATING_VERBS: remove `aws`/`vault`/`glab`/`terraform`/`kubectl`/`helm` regexes; keep
  generic destructive verbs (`rm -rf`, `git push --force`, `git reset --hard`) and the
  prod/deploy/destroy keyword net.
- **`CLAUDE.md`** Safety Guards / architecture prose: drop AWS-profile line and any
  Bedrock/infra-specific rules; keep the local+GitHub safety philosophy.
- **MCP:** in `config/toolkit.md`, mark `sdlc-server` (GitLab wave/PR/CI) and `disc-server`
  (Discord) as **optional/absent on home** — the wave/campaign/disc skills degrade to
  unavailable rather than erroring. Do not remove the skills; note the dependency.

Leave `scripts/env-preflight.sh` as-is (ansible-only, self-contained, no-ops elsewhere).

## §2b. Strip cost machinery (dead on any subscription)

Subscriptions are flat-fee — there is no per-token dollar cost. Remove the dollar-cost
apparatus (the tracking instinct is repurposed as the phase-2 quota bar):

- Delete/neutralize **`scripts/cost-report.sh`** and its tests (`test-cost-report.sh`).
- Remove the **Cost Directive** section from `config/doctrine.md` (the "you run on Opus 4.8
  / 90% trap / downshift-the-spawn" content) — replace with a short **Quota Directive**:
  on a subscription the scarce resource is the usage window, not dollars; conserve Opus
  quota by keeping think-tier lean and delegating formulated work to Sonnet. Keep the
  delegate-heavy-work discipline (still valid), drop the dollar framing.
- Remove the Opus-% cost ledger references from `agents/ledger.md` and the retro/loki docs
  that compute dollar cost. `/retro`'s token section already defers to `/cost`/`/usage`.
- Keep the SessionEnd **model-audit** (proves each agent ran on its intended model) —
  still meaningful; just alias-based per §1.

---

## §3. Vendor BJ's frozen baseline

Target: `vendor/bj-baseline/` on this branch, with a `MANIFEST.md` (what was snapshotted,
from where, on what date, and the SHA/mtime of the source if available).

**Partition rule** — snapshot from `~/.claude/` ONLY the BJ core-workflow assets that
Syndicate does not already reprovide:

- **Syndicate-owned (DO NOT vendor — already in repo `skills/`):** assesswaves, campaign,
  continue, engage, goalseek, godspeed, loki-review, muse, precheck, recall, retro, route,
  status, syndicate, thoughts, wtf.
- **3rd-party design/image plugins (DO NOT vendor — reinstallable separately):** brandkit,
  brutalist-skill, design-taste-frontend, gpt-tasteskill, huashu-design,
  imagegen-frontend-mobile, imagegen-frontend-web, image-to-code-skill, impeccable,
  minimalist-skill, prompt-master, redesign-skill, soft-skill, stitch-skill, ui-ux-pro-max.
- **BJ core workflow (DO vendor — copy `~/.claude/skills/<name>/` for each):** ccfold,
  ccwork, ddd, devspec, disc, dod, edit, ibm, jfail, lazyriver, man, mmr, multithread,
  name, nerf, nextwave, ping, pong, prepwaves, reseed, review, scp, scpmmr, scpmr, sdlc,
  view, vox, and `_shared`. (Verify each exists in `~/.claude/skills/` before copying;
  skip any that don't. If a skill is clearly infra-only — e.g. relies solely on
  gitlab/aws — note it in MANIFEST as "vendored but infra-dependent; may be inert on home.")
- **BJ hooks/config referenced by layered mode:** copy `~/.claude/WAVE_AXIOMS.md`. Copy
  BJ's `~/.claude/settings.json` into `vendor/bj-baseline/settings.reference.json`
  **AFTER sanitizing** — strip any secrets/tokens/paths-with-usernames; it's a *reference*
  for what hooks BJ registers, not a drop-in. If unsure whether a value is sensitive, redact it.

**HARD EXCLUSIONS — never copy, never even read into the repo:**
`~/.claude/.credentials.json`, `~/.claude/projects/`, `~/.claude/history.jsonl`,
`~/.claude/sessions/`, `~/.claude/session-env/`, `~/.claude/shell-snapshots/`,
`~/.claude/file-history/`, `~/.claude/logs/`, `~/.claude/daemon*`, `~/.claude/cache/`,
`~/.claude/paste-cache/`, `~/.claude/plugins/`, `~/.claude/downloads/`, `.credentials*`,
any `*.token`, `*.key`, `*.pem`, `discord.json`, `*-cache.json`.

If any file under a vendored skill dir looks like a credential, skip it and note in MANIFEST.

---

## §4. Install / activation adaptation for home

- **`install.sh`**: keep layered detection (BJ engage marker). Add a note that on the home
  box the BJ layer comes from the vendored `vendor/bj-baseline/` — provide a small
  `scripts/install-bj-baseline.sh` that symlinks/copies the vendored BJ skills into
  `~/.claude/skills/` (skipping any the user already has, non-destructive). Drop the
  Bedrock/aws/glab dependency probes; keep `jq` (hard), `markitdown`/`shellcheck`/`gh`
  (soft warns). Do NOT set model env vars (subscription resolves aliases itself).
- **`config/settings.template.json`** already trimmed in §2. Ensure standalone hook bundle
  references only surviving hooks.
- Update **`README.md`**: a "Home (Pro plan) install" section — checkout `home/lean-pro`,
  run `install.sh`, run `install-bj-baseline.sh`, then the §1 post-install model check
  (`/model`, `/usage`, confirm `opus` resolves or flip think→sonnet). Bump the version line.

---

## §5. Fold in open retro findings

Most open Loki/retro findings dissolve here (model-tier drift → no Bedrock tiers;
cost over-estimate → cost machinery removed). For the rest:
- Ensure the config ships with the install-time model verification step (§1) — this closes
  the "config shipped without model-id verification" finding for the home context.
- The recurring process nags (Scribe-skip, recall-skip) are behavioral, not code — leave
  the doctrine mechanisms intact (they already exist). Do not attempt code "fixes" for them.
- The `stop-action-bias-detector` false-positive item is BJ's hook — out of scope
  (vendored as-is).
- kb-standalone supply-chain note is unrelated to this port — leave it.

---

## §6. Acceptance criteria (Gauntlet/Athena verify)

1. Zero Bedrock ids anywhere on the branch (`grep -rn 'us.anthropic.claude' --include='*.md'
   --include='*.js' --include='*.sh' --include='*.json'` returns nothing outside vendored
   BJ prose or historical notes explicitly quoting the old ids).
2. Every `agents/*.md` `model:` is one of `opus`/`sonnet`/`haiku`; tiering matches §1.
3. No `[1m]` suffixes remain in Syndicate's own config/agents/workflows.
4. Ceph/OpenBao/AWS/Docker/GitLab/LiteLLM absent from Syndicate's own agents/config/
   permissions/settings/hooks (vendored BJ content may still mention them — that's fine).
5. Cost-dollar machinery removed; Quota Directive present.
6. `vendor/bj-baseline/` contains only permitted assets; NONE of the hard-excluded paths;
   `MANIFEST.md` present; `settings.reference.json` sanitized.
7. Adapted `scripts/ci/validate.sh` passes (alias PINNED_MODELS, workflow literals, tiers,
   spawn-authority, secrets scan, lint). `test.sh` green.
8. Nothing blueshift/Analogic anywhere on the branch.
9. Quota bar NOT built here (phase 2).

## Out of scope (phase 2, separate build)
- The usage/quota loading-bar (native statusline feasibility TBD).
