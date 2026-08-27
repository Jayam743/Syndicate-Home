export const meta = {
  name: 'syndicate-pipeline',
  description: 'Standard Syndicate pipeline: Scribe → Forge → Gauntlet → Athena → Hermes → Ledger',
  whenToUse: 'When implementing a feature, fixing a bug, or any code-change task routed through Odin',
  phases: [
    { title: 'Craft', detail: 'Scribe refines the prompt for target agent' },
    { title: 'Build', detail: 'Forge implements the code changes' },
    { title: 'Validate', detail: 'Gauntlet runs tests, Athena reviews in parallel' },
    { title: 'Ship', detail: 'Hermes commits and pushes via /scp flow' },
    { title: 'Record', detail: 'Ledger logs the evidence packet' }
  ]
}

// Standard pipeline: the most common Syndicate flow
// Scribe → Forge → Gauntlet + Athena (parallel) → Hermes → Ledger
//
// Args expected:
//   task: string — the user's original request
//   context: string — relevant file paths, branch, constraints
//   recallBrief / priorContext: string — prior-context brief (past sessions + merge
//       history). If absent, the recall pre-stage runs ~/.syndicate/scripts/recall.sh.
//   skipScribe: boolean — skip prompt crafting for obvious tasks
//   skipScribeReason: string — REQUIRED when skipScribe is set (deterministic gate)
//   skipRecall: boolean — skip the recall pre-stage
//   skipRecallReason: string — REQUIRED when skipRecall is set (deterministic gate)
//   skipTests: boolean — skip Gauntlet (e.g., docs-only changes)

phase('Craft')

// Deterministic preconditions (issue #4): a skip must carry a reason, and recall
// must run unless an explicit, reasoned opt-out is supplied.
if (args.skipScribe && !args.skipScribeReason) {
  return { status: 'failed', stage: 'Craft', reason: 'skipScribe requires skipScribeReason' }
}
if (args.skipRecall && !args.skipRecallReason) {
  return { status: 'failed', stage: 'Craft', reason: 'skipRecall requires skipRecallReason' }
}

// STAGE: recall — ground this run in relevant past sessions + merge history.
let recallBrief = args.recallBrief || args.priorContext || ''
if (args.skipRecall) {
  log(`Recall skipped: ${args.skipRecallReason}`)
} else if (!recallBrief) {
  const recall = await agent(
    `You are running the Syndicate recall pre-stage. Shell out to the recall script
    and return its output verbatim — do NOT investigate or add your own analysis.

    Run: ~/.syndicate/scripts/recall.sh ${JSON.stringify(args.task || '')}

    Return a JSON object with:
    - brief: string — the script's stdout (the context brief), "" if nothing relevant
    - matched: boolean — whether any prior session or merge matched`,
    {
      label: 'recall:prime',
      phase: 'Craft',
      schema: {
        type: 'object',
        properties: { brief: { type: 'string' }, matched: { type: 'boolean' } },
        required: ['brief']
      }
    }
  )
  if (recall && recall.brief) {
    recallBrief = recall.brief
    log(`Recall: prior context loaded${recall.matched ? ' (matches found)' : ''}`)
  } else {
    log('Recall: no relevant prior context found')
  }
}

let refinedPrompt = args.task
let additions = 'none'

// STAGE: scribe — recraft the task into a precise prompt for the target agent.
if (!args.skipScribe) {
  const scribeResult = await agent(
    `You are Scribe. Recraft this task into a precise prompt for Forge (the coder).

    Original task: ${args.task}
    Context: ${args.context || 'none provided'}
    ${recallBrief ? `Prior context (past sessions + merge history):\n${recallBrief}` : ''}

    Return a JSON object with:
    - prompt: the refined prompt for Forge
    - additions: what context you added (one line)
    - targetAgent: "forge" (confirm or override if task needs different agent)`,
    {
      label: 'scribe:recraft',
      phase: 'Craft',
      schema: {
        type: 'object',
        properties: {
          prompt: { type: 'string' },
          additions: { type: 'string' },
          targetAgent: { type: 'string' }
        },
        required: ['prompt', 'additions', 'targetAgent']
      }
    }
  )

  if (scribeResult) {
    refinedPrompt = scribeResult.prompt
    additions = scribeResult.additions
    log(`Scribe refined: +${additions}`)

    if (scribeResult.targetAgent !== 'forge') {
      log(`Scribe re-routed to: ${scribeResult.targetAgent}`)
    }
  }
} else {
  log(`Scribe skipped: ${args.skipScribeReason}`)
}

phase('Build')

const forgeResult = await agent(
  `You are Forge. Implement the following task.

  ${refinedPrompt}
  ${recallBrief ? `\n  Prior context (past sessions + merge history):\n  ${recallBrief}\n` : ''}
  Rules:
  - Read existing code before modifying
  - Match patterns in the codebase
  - Minimal changes — do what was asked, nothing more
  - Report: files modified, what was done, any assumptions

  Return a JSON object with:
  - filesModified: array of file paths changed
  - summary: one-line description of what was implemented
  - assumptions: array of assumptions made (empty if none)
  - followUp: array of things that need follow-up (testing, review concerns)`,
  {
    label: 'forge:implement',
    phase: 'Build',
    schema: {
      type: 'object',
      properties: {
        filesModified: { type: 'array', items: { type: 'string' } },
        summary: { type: 'string' },
        assumptions: { type: 'array', items: { type: 'string' } },
        followUp: { type: 'array', items: { type: 'string' } }
      },
      required: ['filesModified', 'summary']
    }
  }
)

if (!forgeResult) {
  log('Forge failed — pipeline halted')
  return { status: 'failed', stage: 'Build', reason: 'Forge returned null' }
}

log(`Forge done: ${forgeResult.summary} (${forgeResult.filesModified.length} files)`)

phase('Validate')

const validationResults = await parallel([
  // Gauntlet: run tests
  () => {
    if (args.skipTests) {
      log('Gauntlet skipped (no-test flag)')
      return { passed: true, skipped: true, summary: 'Tests skipped by user' }
    }
    return agent(
      `You are Gauntlet. Run the project's test suite.

      Files that were just modified: ${forgeResult.filesModified.join(', ')}

      1. Detect the test framework (pytest, jest, go test, etc.)
      2. Run the relevant tests
      3. Report pass/fail

      Return a JSON object with:
      - passed: boolean
      - testsRun: number
      - testsFailed: number
      - failures: array of {name, reason} for any failures
      - summary: one-line result`,
      {
        label: 'gauntlet:test',
        phase: 'Validate',
        schema: {
          type: 'object',
          properties: {
            passed: { type: 'boolean' },
            testsRun: { type: 'number' },
            testsFailed: { type: 'number' },
            failures: { type: 'array', items: { type: 'object', properties: { name: { type: 'string' }, reason: { type: 'string' } } } },
            summary: { type: 'string' }
          },
          required: ['passed', 'summary']
        }
      }
    )
  },
  // Athena: review
  () => agent(
    `You are Athena. Review the code changes just made by Forge.

    Files modified: ${forgeResult.filesModified.join(', ')}
    What was implemented: ${forgeResult.summary}
    Original task: ${args.task}

    Check: correctness, security, edge cases, logic errors, integration risks.
    Only report findings at 80%+ confidence. No style nitpicks.

    Return a JSON object with:
    - clean: boolean (true if no issues found)
    - findings: array of {severity, file, line, issue, fix}
    - summary: one-line verdict`,
    {
      label: 'athena:review',
      phase: 'Validate',
      schema: {
        type: 'object',
        properties: {
          clean: { type: 'boolean' },
          findings: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                severity: { type: 'string' },
                file: { type: 'string' },
                line: { type: 'number' },
                issue: { type: 'string' },
                fix: { type: 'string' }
              }
            }
          },
          summary: { type: 'string' }
        },
        required: ['clean', 'summary']
      }
    }
  )
])

const [testResult, reviewResult] = validationResults

// Check test results
if (testResult && !testResult.passed && !testResult.skipped) {
  log(`Gauntlet FAILED: ${testResult.summary}`)
  return {
    status: 'failed',
    stage: 'Validate',
    reason: 'Tests failed',
    testResult,
    reviewResult
  }
}

if (testResult) {
  log(`Gauntlet: ${testResult.summary}`)
}

// Check review results — critical findings halt
if (reviewResult && !reviewResult.clean) {
  const criticals = (reviewResult.findings || []).filter(f => f.severity === 'critical')
  if (criticals.length > 0) {
    log(`Athena found ${criticals.length} CRITICAL issue(s) — pipeline halted`)
    return {
      status: 'blocked',
      stage: 'Validate',
      reason: 'Critical review findings',
      reviewResult,
      testResult
    }
  }
  log(`Athena: ${reviewResult.findings.length} finding(s) (non-critical, logged as concerns)`)
} else if (reviewResult) {
  log(`Athena: ${reviewResult.summary}`)
}

phase('Ship')

const hermesResult = await agent(
  `You are Hermes. Commit and push the changes made by Forge — CONTEXT-AWARE.

  Files modified: ${forgeResult.filesModified.join(', ')}
  Summary: ${forgeResult.summary}
  Original task: ${args.task}

  Context-aware pre-flight (do this FIRST — it's your edge over mechanical git):
  0a. Read the actual diff: git diff --cached (or git diff of the modified files).
      Draft the commit message FROM the diff, not from the summary above.
  0b. git log --oneline -20 — mirror the repo's real commit style.
  0c. git log --merges --oneline -15 — detect the real target branch (don't assume
      main) and flag if this change duplicates something recently merged.

  Then:
  1. Run git status to confirm changes
  2. Stage the modified files
  3. Commit with a conventional message drafted from the diff (type(scope): description)
  4. Push to the correct branch

  Use the /scp skill flow if available, otherwise:
  - git add [files]
  - git commit -m "type(scope): description"
  - git push

  Return a JSON object with:
  - committed: boolean
  - commitHash: string (short hash)
  - commitMessage: string
  - pushed: boolean
  - branch: string
  - targetBranch: string — the branch targeted, and why (e.g. "release/2.0.1: last 6 merges")
  - duplicateWarning: string or null — set if this change looks like recent merged work
  - prUrl: string or null`,
  {
    label: 'hermes:ship',
    phase: 'Ship',
    schema: {
      type: 'object',
      properties: {
        committed: { type: 'boolean' },
        commitHash: { type: 'string' },
        commitMessage: { type: 'string' },
        pushed: { type: 'boolean' },
        branch: { type: 'string' },
        targetBranch: { type: 'string' },
        duplicateWarning: { type: ['string', 'null'] },
        prUrl: { type: ['string', 'null'] }
      },
      required: ['committed', 'commitMessage', 'branch']
    }
  }
)

if (hermesResult && hermesResult.duplicateWarning) {
  log(`Hermes ⚠ possible duplicate: ${hermesResult.duplicateWarning}`)
}

if (!hermesResult || !hermesResult.committed) {
  log('Hermes failed to commit — check precheck/test-gate status')
  return {
    status: 'blocked',
    stage: 'Ship',
    reason: 'Commit/push failed',
    hermesResult
  }
}

log(`Hermes: ${hermesResult.commitMessage} → ${hermesResult.branch}`)

phase('Record')

const evidence = await agent(
  `You are Ledger. Record this completed pipeline as an evidence packet.

  Pipeline: Scribe → Forge → Gauntlet → Athena → Hermes
  Task: ${args.task}
  Outcome: ${forgeResult.summary}
  Files: ${forgeResult.filesModified.join(', ')}
  Tests: ${testResult ? testResult.summary : 'skipped'}
  Review: ${reviewResult ? reviewResult.summary : 'skipped'}
  Commit: ${hermesResult.commitMessage} (${hermesResult.commitHash || 'unknown'})
  Branch: ${hermesResult.branch}

  Write a one-line entry to ~/.syndicate/ledger/current-week.md
  Then return the evidence summary.

  Return a JSON object with:
  - logged: boolean
  - entry: string (the ledger line)`,
  {
    label: 'ledger:record',
    phase: 'Record',
    schema: {
      type: 'object',
      properties: {
        logged: { type: 'boolean' },
        entry: { type: 'string' }
      },
      required: ['logged', 'entry']
    }
  }
)

if (evidence) {
  log(`Ledger: ${evidence.entry}`)
}

return {
  status: 'complete',
  task: args.task,
  summary: forgeResult.summary,
  filesModified: forgeResult.filesModified,
  commit: hermesResult.commitMessage,
  branch: hermesResult.branch,
  pr: hermesResult.prUrl,
  tests: testResult ? testResult.summary : 'skipped',
  review: reviewResult ? reviewResult.summary : 'skipped',
  concerns: reviewResult && !reviewResult.clean ? reviewResult.findings : []
}
