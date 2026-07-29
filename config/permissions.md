# Agent Permission Reference

This documents what each agent typically runs. Use this as a reference when
deciding what to add to `~/.claude/settings.json` allowedTools.

**This file is NOT enforcement** — it's a reference. The real enforcement is
`settings.json` + BJ's hooks.

## Per-Agent Typical Commands

### Odin (orchestrator)
- Spawns other agents via Agent tool (always allowed)
- No direct system commands

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
- `docker logs`, `docker ps`, `docker exec` (READ-ONLY inspection)
- `aws ... describe-*`, `aws ... list-*`, `aws ... get-*` (read-only)
- `curl`, `wget` (health checks)
- `systemctl status`, `journalctl` (service inspection)
- `ssh` + read-only commands via SSM
- Never: restart, stop, modify, delete

### Hermes (git ops)
- `git add`, `git commit`, `git push`
- `git checkout -b`, `git branch`
- `glab mr create`, `gh pr create`
- `git status`, `git log`, `git diff`

### Titan (infra)
- `aws --profile X ... describe-*` (read-only default)
- `terraform plan` (read-only)
- `docker ps`, `docker inspect` (read-only)
- Mutating: ONLY with explicit user approval

### Safecracker (secrets)
- `vault read`, `vault write` (vault ops)
- `aws secretsmanager get-secret-value`
- `openssl rand` (key generation)
- Never: print plaintext secrets in output

### Ledger (tracker)
- `git log` across repos (data gathering)
- File reads (transcripts)
- File writes (ledger log only)
- `glab mr list`, `gh pr list`

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
