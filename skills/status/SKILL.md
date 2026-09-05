---
name: status
description: "Gather genuine git history for a Thu→Wed week, synthesize thematic bullets via Ledger, render a Word .docx into the Desktop Weekly Logs folder, and PREVIEW it (never auto-file)."
---

# /status — Weekly Status Report (docx)

Builds the operator's weekly status report from GENUINE git history and renders it
to a Word `.docx` for review. The LLM (Ledger) produces DATA (a JSON payload); the
python script (`scripts/gen_weekly_status.py`) does deterministic rendering. This
skill NEVER auto-files — it previews, and the operator pastes into the shared files.

## Trigger

- `/status` — the Thu→Wed period CONTAINING today
- `/status --last` — the prior completed Thu→Wed week
- `/status 2026-09-02` — the Thu→Wed week whose Wednesday is that end-date
- `/status 2026-08-27 2026-09-02` — an explicit range

## Config

Read `config/weekly-status.json`:
- `display_name` — name at the top of the report
- `authors[]` — git author names/emails to match
- `work_root` — directory to GLOB for git repos (do NOT hardcode a repos[] list;
  an optional `repos[]` key MAY override the glob, but glob is the default so a
  newly-added repo is never silently under-counted)
- `out_dir` — output folder; overridable via `SYNDICATE_STATUS_OUT_DIR` env var and
  supports `~` expansion (it is a Windows Desktop path — a personal-tool portability
  smell; it is overridable, not shareable)

## Procedure

### 1. Window math (single source of truth)
Default window = the Thu→Wed period CONTAINING today. Also accept an explicit
end-date, an explicit range, or `--last` (prior completed week).
- `--since` = **Thursday 00:00:00 local**
- `--until` = **the following Thursday 00:00:00 local** (EXCLUSIVE upper bound — this
  captures all of Wednesday)
- Use `--date=local` and the operator's local timezone (WSL2 inherits it) so a
  Wednesday-evening local commit does not slip into next week via UTC.
- Human-facing label "Week ending <Wed>" = the exclusive `--until` bound minus one day.

### 2. Discover repos
Glob `work_root` for directories containing a `.git` entry. If `repos[]` is set in
config, use that list instead.

### 3. Gather (per repo)
For content:
```
git -C <repo> log --all \
  --author='Jayam Patel\|Jbpatel\|jpatel' \
  --since='<thu 00:00:00>' --until='<next-thu 00:00:00>' \
  --date=local --no-merges --pretty='%h %ad %s'
```
Also count merge commits by those authors in the same window for the "MRs merged"
metric. `--all` is REQUIRED — merged-but-not-on-HEAD work must not drop.

### 4. GENUINE-DATA GUARD (the single most important rule)
- If any discovered repo returns **zero commits** in the window, FLAG it in the
  preview: `repo X: 0 commits this window — confirm or drop`. Never synthesize
  around a thin/empty week.
- The preview MUST print: the matched-author filter used, and the total commits
  scanned per repo — so an undercount is visible to the operator BEFORE submit.
- Never pad. If a week is thin, the report is short.

### 5. Synthesize (Ledger → JSON payload)
Ledger distills the git data into a JSON payload. GENUINE ONLY — every bullet must
trace to a real commit in the gathered log.

- Group into **themes by area** (repo in parens), each theme = a bold lead-in plus
  2–4 crisp detail sub-bullets.
- **Anti-pattern — do NOT do this (the rejected 8-11 style):** listing work
  MR-by-MR, one bullet per merge request. That is a raw changelog, not a status.
- **Approved (the 8-18 style):** thematic grouping, where each theme summarizes
  several related commits/MRs into one narrative lead-in with detail sub-bullets.

Payload shape (all 6 keys required, all non-empty):
```json
{
  "week_range_label": "Week of Thu Aug 27 – Wed Sep 2, 2026",
  "filename": "Weekly Status - Patel, Jayam - Week ending 2026-09-02.docx",
  "accomplishments": [
    {
      "theme": "Auth service hardening (example-api):",
      "details": [
        "Built token refresh deriving state from history (#238) and a leak-proof JIT-token session store (#234)",
        "Shipped a scriptable admin CLI (#240) and approval verification (#241)",
        "Closed the loop with teardown and full close (#275)"
      ]
    },
    {
      "theme": "Config-as-code (example-infra):",
      "details": [
        "Shipped the bootstrap playbook to config-as-code the hand-built substrate",
        "Migrated the app DB from SQLite to Postgres with a retention cap"
      ]
    }
  ],
  "blockers": "None active. The within-week correctness bug (#269) was caught and fixed the same week, not carried forward.",
  "track": "Ahead. 55 MRs merged across three repos this week (ansible 15, agent-mantle 26, manifests 14) — up from 34 last week.",
  "next_obj": "Continue hardening the Cotterpin engagement lifecycle and build out Salvo's config-as-code surface; keep manifests digest-pinned to agent-mantle releases."
}
```
Note the sections and the UTF-8 typography (curly quotes “ ”, en/em-dashes – —).
There is NO "release" line — the operator does not ship releases.

### 6. Render + preview
- Write the payload to a temp file (UTF-8).
- Text preview: `python3 scripts/gen_weekly_status.py --text <tmp.json>` and show the
  operator the terminal preview alongside the GENUINE-DATA GUARD output from step 4.
- Render the docx: `python3 scripts/gen_weekly_status.py --payload <tmp.json>` and
  show the operator the saved path.
- NEVER auto-submit / auto-file. The operator pastes into the shared SWE/SQA files
  themselves.

### 7. Sections
Accomplishments / Blockers + mitigation / On track–behind–ahead / Next week's
objectives. No "release" line.
