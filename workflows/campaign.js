export const meta = {
  name: 'syndicate-campaign',
  description: 'Multi-issue campaign: decompose work into waves, execute each wave autonomously',
  whenToUse: 'When tackling 4+ related issues/tasks that can be batched into dependency waves',
  phases: [
    { title: 'Decompose', detail: 'Break work into dependency-ordered waves' },
    { title: 'Execute', detail: 'Run each wave (serial waves, parallel items within)' },
    { title: 'Report', detail: 'Summary of campaign results' }
  ]
}

// Campaign workflow: wave-pattern execution for multi-issue work
//
// Args expected:
//   issues: array of {id, title, description, dependencies} — the work items
//   repo: string — target repository path
//   branch: string — base branch to work from
//   autoMerge: boolean — auto-merge small PRs (requires all gates green)
//   maxWaves: number — safety cap on wave count (default 5)
//
// The wave pattern:
// 1. Decompose issues into dependency-ordered waves
// 2. Within each wave, items can run in parallel (no inter-dependencies)
// 3. Between waves, there's a barrier (wave N+1 depends on wave N)
// 4. Each item goes through the standard pipeline
// 5. Campaign completes when all waves done

phase('Decompose')

const issues = args.issues || []
const maxWaves = args.maxWaves || 5

if (issues.length === 0) {
  log('No issues provided — campaign cannot start')
  return { status: 'failed', reason: 'No issues provided' }
}

if (issues.length < 2) {
  log('Only 1 issue — use standard-pipeline instead of campaign')
  return { status: 'redirect', reason: 'Single issue does not need campaign', useInstead: 'syndicate-pipeline' }
}

log(`Campaign: ${issues.length} issues to decompose into waves`)

const decomposition = await agent(
  `You are Odin planning a campaign. Decompose these issues into dependency-ordered waves.

  ISSUES:
  ${issues.map(i => `- [${i.id}] ${i.title}: ${i.description || 'no description'}${i.dependencies ? ` (depends on: ${i.dependencies.join(', ')})` : ''}`).join('\n')}

  RULES:
  - Wave 1: issues with NO dependencies (can start immediately)
  - Wave 2: issues that depend ONLY on Wave 1 items
  - Wave N: issues that depend on items in waves 1..N-1
  - Within a wave, items have NO inter-dependencies (can run in parallel)
  - Maximum ${maxWaves} waves — if more are needed, something is wrong
  - If circular dependencies exist, flag them

  Return a JSON object with:
  - waves: array of {waveNumber, items: array of issue IDs in this wave}
  - topology: "serial" | "parallel" | "mixed" (what the dependency graph looks like)
  - circularDeps: array of issue IDs involved in cycles (empty if none)
  - estimatedEffort: string (total time estimate)
  - rationale: string (one line explaining the decomposition)`,
  {
    label: 'odin:decompose',
    phase: 'Decompose',
    schema: {
      type: 'object',
      properties: {
        waves: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              waveNumber: { type: 'number' },
              items: { type: 'array', items: { type: 'string' } }
            },
            required: ['waveNumber', 'items']
          }
        },
        topology: { type: 'string' },
        circularDeps: { type: 'array', items: { type: 'string' } },
        estimatedEffort: { type: 'string' },
        rationale: { type: 'string' }
      },
      required: ['waves', 'topology']
    }
  }
)

if (!decomposition) {
  log('Decomposition failed')
  return { status: 'failed', stage: 'Decompose', reason: 'Could not decompose issues' }
}

if (decomposition.circularDeps && decomposition.circularDeps.length > 0) {
  log(`BLOCKED: Circular dependencies detected: ${decomposition.circularDeps.join(', ')}`)
  return {
    status: 'blocked',
    stage: 'Decompose',
    reason: 'Circular dependencies',
    circularDeps: decomposition.circularDeps
  }
}

log(`Decomposed: ${decomposition.waves.length} waves, topology=${decomposition.topology}`)
log(`  ${decomposition.rationale}`)

phase('Execute')

const waveResults = []
let campaignFailed = false

for (const wave of decomposition.waves) {
  if (campaignFailed) break

  log(`═══ Wave ${wave.waveNumber}/${decomposition.waves.length}: ${wave.items.length} item(s) ═══`)

  const waveIssues = wave.items.map(id => issues.find(i => i.id === id)).filter(Boolean)

  // Execute items within this wave in parallel
  const itemResults = await parallel(
    waveIssues.map(issue => () =>
      agent(
        `You are executing a campaign item. Implement this issue end-to-end.

        ISSUE: [${issue.id}] ${issue.title}
        DESCRIPTION: ${issue.description || 'see title'}
        REPO: ${args.repo || 'current directory'}
        BASE BRANCH: ${args.branch || 'current branch'}

        Steps:
        1. Create a feature branch: feat/${issue.id}-${issue.title.toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 30)}
        2. Implement the change
        3. Run tests
        4. Commit with conventional format: feat(scope): description (Closes #${issue.id})
        5. Push and create PR/MR

        Return a JSON object with:
        - issueId: "${issue.id}"
        - status: "complete" | "failed" | "blocked"
        - branch: string (branch name created)
        - filesModified: array of file paths
        - commitMessage: string
        - prUrl: string or null
        - testsPassed: boolean
        - error: string or null (if failed/blocked)`,
        {
          label: `wave${wave.waveNumber}:${issue.id}`,
          phase: 'Execute',
          schema: {
            type: 'object',
            properties: {
              issueId: { type: 'string' },
              status: { type: 'string' },
              branch: { type: 'string' },
              filesModified: { type: 'array', items: { type: 'string' } },
              commitMessage: { type: 'string' },
              prUrl: { type: ['string', 'null'] },
              testsPassed: { type: 'boolean' },
              error: { type: ['string', 'null'] }
            },
            required: ['issueId', 'status']
          }
        }
      )
    )
  )

  const waveReport = {
    waveNumber: wave.waveNumber,
    items: itemResults.filter(Boolean),
    failed: itemResults.filter(r => r && r.status === 'failed'),
    succeeded: itemResults.filter(r => r && r.status === 'complete'),
    blocked: itemResults.filter(r => r && r.status === 'blocked')
  }

  waveResults.push(waveReport)

  log(`  Wave ${wave.waveNumber} results: ${waveReport.succeeded.length} complete, ${waveReport.failed.length} failed, ${waveReport.blocked.length} blocked`)

  // If ANY item in this wave failed with a hard error, halt campaign
  // (Axiom 6: concerns don't block, but hard faults do)
  if (waveReport.failed.length > 0) {
    const hardFaults = waveReport.failed.filter(f => f.error && !f.error.includes('concern'))
    if (hardFaults.length > 0) {
      log(`Campaign HALTED: hard fault in wave ${wave.waveNumber}`)
      campaignFailed = true
    }
  }
}

phase('Report')

const totalItems = issues.length
const completedItems = waveResults.flatMap(w => w.succeeded).length
const failedItems = waveResults.flatMap(w => w.failed).length
const blockedItems = waveResults.flatMap(w => w.blocked).length

const summary = `Campaign: ${completedItems}/${totalItems} complete, ${failedItems} failed, ${blockedItems} blocked`
log(summary)

// Write evidence for the whole campaign
const allPRs = waveResults
  .flatMap(w => w.succeeded)
  .filter(r => r.prUrl)
  .map(r => r.prUrl)

return {
  status: campaignFailed ? 'partial' : 'complete',
  summary,
  waves: decomposition.waves.length,
  topology: decomposition.topology,
  results: {
    total: totalItems,
    completed: completedItems,
    failed: failedItems,
    blocked: blockedItems
  },
  prs: allPRs,
  waveDetails: waveResults.map(w => ({
    wave: w.waveNumber,
    succeeded: w.succeeded.map(s => s.issueId),
    failed: w.failed.map(f => ({ id: f.issueId, error: f.error })),
    blocked: w.blocked.map(b => ({ id: b.issueId, error: b.error }))
  }))
}
