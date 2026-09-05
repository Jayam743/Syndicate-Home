# Agent Permission Reference

This documents what each agent typically runs. Use this as a reference when
deciding what to add to `~/.claude/settings.json` allowedTools.

**This file is NOT enforcement** — it's a reference. The real enforcement is
`settings.json` + BJ's hooks.

## Per-Agent Typical Commands

### Odin (orchestrator)
- Spawns other agents via Agent tool (always allowed)
- Runs Workflows (standard-pipeline, campaign, goalseek, etc.)
- No direct system commands

### Muse (conception partner)
- File reads (context for shaping)
- File writes (decision ledger only — `~/.syndicate/conception/`)
- `git log`, `git diff` (understanding what exists before shaping)
- No code changes, no spawning (Axiom 11)

### Scribe (prompt crafter)
- `git branch --show-current` (context gathering)
- `git remote -v` (platform detection)
- File reads (for context)
- No mutations

### Forge (coder)
- File reads/writes/edits (core job)
- `git diff`, `git status` (awareness)
- Language-specific: `python`, `node`, `mvn`, `cargo`, etc.
- Never: `git push`, `git commit` (that's Hermes)

### Athena (reviewer)
- File reads (core job)
- `grep`, `find` (searching for patterns)
- `git diff`, `git log` (understanding changes)
- Never: file writes (she reviews, doesn't fix)

### Gauntlet (tester)
- `pytest`, `npm test`, `mvn test`, `go test`, etc.
- `make test`, `./scripts/ci/test.sh`
- File reads (test files)
- File writes (only test files)

### Specter (investigator)
- `curl`, `wget` (health checks)
- `systemctl status`, `journalctl` (local service inspection)
- Process/filesystem inspection (`ps`, `ls`, `find`, log reads)
- Never: restart, stop, modify, delete

### Hermes (git ops)
- `git add`, `git commit`, `git push`
- `git checkout -b`, `git branch`
- `gh pr create`
- `git status`, `git log`, `git diff`

### Titan (local dev/system ops)
- Local process/filesystem inspection (`ps`, `ls`, `find`, `systemctl status`)
- `git`, build/run of local dev tooling (read-only default)
- Mutating local ops: ONLY with explicit user approval

### Safecracker (local secret hygiene)
- `.env` / `.gitignore` inspection and hygiene checks
- `gh secret` (GitHub repo/environment secrets)
- `openssl rand` (key generation)
- Never: print plaintext secrets in output

### Ledger (tracker)
- `git log` across repos (data gathering)
- File reads (transcripts)
- File writes (ledger log only)
- `gh pr list`

### Herald (messenger)
- File reads (context for drafting)
- No system commands — just text output

### Cipher (doc ingestion)
- `markitdown` (conversion)
- File reads/writes (.md output)

### Loki (devil's advocate)
- File reads (reviewing agent output)
- File writes (loki/logs/ only)
- `git log`, `git diff` (checking what actually happened)

## Recommended settings.json Additions

These are safe to allow without prompting (all read-only):

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git branch --show-current)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git remote -v)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(cat *)",
      "Bash(ls *)",
      "Bash(wc *)"
    ]
  }
}
```

For per-agent context, the real enforcement is BJ's hooks. The stop-action-detector
catches prod/irreversible keywords regardless of which agent triggered it.
