# Vendored BJ Baseline — MANIFEST

Frozen snapshot of BJ's CC-workflow core assets, vendored into the `home/lean-pro`
branch so the home (Pro subscription) box can run "BJ's workflow + Syndicate layered on
top" without fetching from BJ's live upstream (which has since been containerized).

## Provenance

- **Source:** `~/.claude/skills/`, `~/.claude/WAVE_AXIOMS.md`, `~/.claude/settings.json`
  on the operator's machine.
- **Snapshot date:** 2026-09-05.
- **Source SHA:** none — `~/.claude` and `~/.claude/skills` are NOT git repositories, so
  there is no commit SHA to record. Provenance is by mtime instead.
- **Source mtime:** vendored skill files carry mtimes of ~2026-07-16 (BJ's last workflow
  drop into this machine).

## What was vendored

### `skills/` — 31 BJ-core workflow skills (copied verbatim from `~/.claude/skills/<name>/`)

ccwork, ddd, devspec, disc, dod, edit, grunt, ibm, jfail, lazyriver, man, mmr,
multithread, name, nerf, nextwave, ping, pong, prepwaves, reseed, review, scp, scpmmr,
scpmr, sdlc, view, vox, wtf-happened, wtf-imout, wtf-now, `_shared`.

27 of the 28 originally named in the spec's DO-vendor list were present in
`~/.claude/skills/` and copied. **`ccfold` was later REMOVED** from the vendor set (see
"Removed after initial vendoring" below) — it is not part of the final 31. The 31 total
= 27 (DO-vendor list, minus ccfold) + 4 (`grunt`, `wtf-happened`, `wtf-imout`, `wtf-now`
— added post-review; see "Post-review addition" below).

**Infra-dependent (vendored as-is; may be inert on a GitHub-only home box):** several of
these skills reference GitLab/`glab`/`aws`/`terraform` in their procedures — notably
`scp`, `scpmr`, `scpmmr`, `mmr`, `sdlc`, `jfail`, and `ccwork` (git-forge / CI flows
built around GitLab). On home (GitHub-only, no AWS/GitLab), those specific code paths may
be inert or degrade; the skills are still vendored intact per the partition rule.

### Removed after initial vendoring — `ccfold`

**`ccfold` was vendored, then REMOVED** (`rm -rf vendor/bj-baseline/skills/ccfold/`) on
review. Reason: it is a GitLab-org-identity mapping skill — inert on a GitHub-only home
box — AND its `SKILL.md` contains real corporate PII/org names (`jpatel@analogic.com`,
`brbaker@analogic.com`, `bakerb@waveeng.com`, the `analogicdev` GitLab org map). That
violates the operator's absolute "nothing blueshift/Analogic" fence (acceptance
criterion §6.8) — no carve-out applies. `ccfold` is now excluded, not vendored; see
"What was NOT vendored" below.

### Post-review addition — 4 skills toolkit.md referenced but the initial pass missed

`grunt`, `wtf-happened`, `wtf-imout`, `wtf-now` were flagged in the original MANIFEST as
"present but not in any partition list" (see the old FLAG note, now resolved). Since
Syndicate's own `config/toolkit.md` references all four (`/grunt`, `/wtf-now`,
`/wtf-happened`, `/wtf-imout`), each was scanned before vendoring:
`grep -riE 'blueshift|analogic|waveeng|@analogic' <skilldir>` → **zero matches** for all
four, and no hard-excluded file patterns (`*.token`/`*.key`/`*.pem`/cache files) or
secret-content patterns present. All four vendored clean.

### `WAVE_AXIOMS.md`

Copied verbatim from `~/.claude/WAVE_AXIOMS.md` (324 lines) — the wave/campaign axioms
BJ's layered mode references.

### `settings.reference.json`

Sanitized copy of `~/.claude/settings.json`. It is a **reference** for which hooks BJ's
workflow registers (and in what lifecycle slots), NOT a drop-in. Sanitization applied:

- `env.AWS_PROFILE` value redacted → `<REDACTED>` (org bot-profile name).
- Username-bearing absolute path (`/home/jpatel/.local/share/wtf-server/...`) rewritten
  to `~/.local/share/...`.
- The `Stop` wavemachine-stall-guard inline shell (a large verbatim script) was elided
  to a placeholder — not a secret, just noise for a hooks reference.
- The `enabledPlugins` block was omitted (it lists reinstallable official plugins, not
  hook wiring; out of scope for a hooks reference).
- The `env` block is BJ's **Bedrock** config and does NOT apply to a home Pro
  subscription — do not set model env vars on home (aliases resolve directly).

No tokens, keys, passwords, or credentials were present in the source settings file.

## What was NOT vendored (and why)

### Syndicate-owned skills (already in the repo `skills/`) — DO NOT vendor

assesswaves, campaign, continue, engage, goalseek, godspeed, loki-review, muse, precheck,
recall, retro, route, status, syndicate, thoughts, wtf.

### 3rd-party design/image plugins (reinstallable separately) — DO NOT vendor

brandkit, brutalist-skill, design-taste-frontend, gpt-tasteskill, huashu-design,
imagegen-frontend-mobile, imagegen-frontend-web, image-to-code-skill, impeccable,
minimalist-skill, prompt-master, redesign-skill, soft-skill, stitch-skill, ui-ux-pro-max.

(All 15 were present in `~/.claude/skills/` and deliberately left un-vendored.)

### `ccfold` — DO NOT vendor (fence violation, removed after initial vendoring)

**Reason: "GitLab-org-identity skill, inert on GitHub home + real corporate PII/org
names → violates fence #8."** `ccfold` maps GitLab org → git identity
(`analogicdev` → `brbaker@analogic.com`, with a fallback baseline referencing
`bakerb@waveeng.com`); it has no function on a GitHub-only home box, and its content
directly names the excluded employer/org. See "Removed after initial vendoring" above.

## Hard exclusions — verified NOT copied / NOT read

None of the hard-excluded paths were copied or read into the repo:
`.credentials.json`, `projects/`, `history.jsonl`, `sessions/`, `session-env/`,
`shell-snapshots/`, `file-history/`, `logs/`, `daemon*`, `cache/`, `paste-cache/`,
`plugins/`, `downloads/`, `discord.json`, any `*.token`/`*.key`/`*.pem`/`*-cache.json`.

Post-copy scan of `vendor/bj-baseline/skills/` found:
- zero files matching excluded name patterns (`*.token`, `*.key`, `*.pem`,
  `*-cache.json`, `discord.json`, `.credentials*`);
- zero files matching secret content patterns (GitHub/GitLab PATs, OpenAI/Anthropic
  keys, Slack tokens, AWS access keys, PEM blocks).

Post-review re-scan (after removing `ccfold` and adding `grunt`/`wtf-happened`/
`wtf-imout`/`wtf-now`) additionally confirmed zero matches for
`blueshift|analogic|waveeng|@analogic` across the entire vendored skill tree.

Total vendored skills size: ~384K (31 skills).

## Resolved — BJ skills present but NOT in any partition list

The original build flagged 7 BJ skills present in `~/.claude/skills/` but named in none
of the spec's three partition lists. On review this resolved as follows:

- **Vendored** (scanned clean, toolkit.md references them): `grunt`, `wtf-happened`,
  `wtf-imout`, `wtf-now` — see "Post-review addition" above.
- **NOT vendored — `config/toolkit.md` repoints instead:** `issue`, `wave`,
  `wavemachine`. `wave`/`wavemachine` are marked OPTIONAL/absent-on-home in
  `config/toolkit.md` (same treatment as `sdlc-server`, since they are wave/campaign
  MCP-adjacent skills BJ's workflow provides). The `/issue` reference in `toolkit.md`
  is repointed to GitHub-native `gh issue` rather than vendoring the skill, since
  `gh issue` covers the same need without adding another BJ skill dependency.
