---
name: precheck
description: "Pre-commit gate — validate branch, review code, run checklist. Mandatory before every commit."
---

# /precheck — Syndicate Pre-Commit Gate

Mandatory gate before any commit. This is NOT optional. Agents RUN it, don't ask about it.

## Trigger

`/precheck` — runs automatically before any commit in the pipeline

## Procedure

1. **Branch validation**
   - Is current branch NOT main/master? (never commit to protected branches)
   - Does branch name follow convention? (`feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`)
   - Does branch name include issue number if available?

2. **Staged files check**
   - Run `git status`
   - Are there actually files staged? (don't commit nothing)
   - Do any staged files match secret patterns? (.env, .key, .pem, credentials)
   - Flag any unexpectedly large files (> 1MB)

3. **Quick code review**
   - Run `git diff --cached` (staged changes only)
   - Check for: debug statements left in (`console.log`, `print(`, `debugger`, `TODO: remove`)
   - Check for: hardcoded URLs pointing to localhost/dev that shouldn't be committed
   - Check for: commented-out code blocks (more than 5 lines)

4. **Commit message check**
   - Format: `type(scope): description`
   - Types: feat, fix, docs, style, refactor, test, chore
   - Description is present and meaningful (not "fix" or "update")

5. **Report**

```
═══ PRECHECK ═══
Branch: ✓ fix/123-login-timeout (valid)
Staged: ✓ 3 files, no secrets, no oversized
Review: ✓ clean (no debug/todo/commented code)
Message: ✓ fix(auth): handle session timeout gracefully

PASSED — safe to commit.
```

Or:

```
═══ PRECHECK ═══
Branch: ✓ fix/123-login-timeout
Staged: ✗ BLOCKED — .env.local staged (secret pattern)
Review: ⚠ console.log on line 42 of src/auth.js
Message: ✓ valid

FAILED — fix issues before committing.
```

## Behavior

- If PASSED: proceed with commit (no further confirmation needed)
- If FAILED with warnings only (⚠): report warnings, ask user if proceed
- If FAILED with blocks (✗): STOP. Do not commit. Report what needs fixing.

## Integration

- When BJ's workflow `/precheck` exists: defer to that (it's more comprehensive)
- Standalone: this skill provides the minimum viable gate
- Hermes calls this automatically — it does NOT ask "shall I run precheck?"

## Notes

- This skill exists for standalone Syndicate users
- BJ's workflow users already have a more comprehensive `/precheck`
- The installer detects which one to use (BJ's takes priority)
