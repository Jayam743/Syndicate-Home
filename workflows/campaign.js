export const meta = {
  name: 'syndicate-campaign',
  description: 'Multi-issue campaign: decompose work into waves, execute each wave autonomously',
  whenToUse: 'When tackling 4+ related issues/tasks that can be batched into dependency waves',
  phases: [
    { title: 'Decompose', detail: 'Break work into dependency-ordered waves' },
    { title: 'Execute', detail: 'Run each wave; dispatch serial by default, fan out only when verified safe' },
    { title: 'Oversee', detail: 'Between waves: judge trajectory against intent + prior sessions; HOLD if drifting' },
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
//   intent: string — the campaign's overall goal (what the whole batch is FOR).
//           Used by the oversight seam to judge trajectory drift.
//   priorContext: string — recall brief (relevant past sessions + merge history).
//           Odin fills this from ~/.syndicate/scripts/recall.sh so oversight judges against
//           history, not just this run. This is what BJ's stateless design can't do.
//   overseeConfidenceFloor: number 0-100 — HOLD if oversight confidence drops
//           below this (default 50).
//
// The wave pattern:
// 1. Decompose issues into dependency-ordered waves
// 2. Within each wave, items can run in parallel (no inter-dependencies)
// 3. Between waves, there's a barrier (wave N+1 depends on wave N)
// 4. Each item goes through the standard pipeline
// 5. BETWEEN waves, an oversight SEAM judges trajectory (control flow is code;
//    judgment is a seam — the overseer is a distinct campaign-altitude judge,
//    NOT one of the execution agents reused)
// 6. Campaign completes when all waves done, or HOLDs if oversight flags drift

phase('Decompose')

const issues = args.issues || []
const maxWaves = args.maxWaves || 5
const campaignIntent = args.intent || '(intent not stated — infer from the issue set)'
const priorContext = args.priorContext || '(no prior context supplied)'
const confidenceFloor = args.overseeConfidenceFloor || 50

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
  - Within a wave, items have NO inter-dependencies
  - Maximum ${maxWaves} waves — if more are needed, something is wrong
  - If circular dependencies exist, flag them

  DISPATCH CLASSIFICATION (per wave) — this decides serial vs parallel execution.
  The bias is ASYMMETRIC: default to serial, only fan out when verified safe.
  A wrong "serialize" costs wall-clock; a wrong "fan" can invalidate the whole
  wave (two agents editing overlapping files, clobbering each other).

  Classify each wave's dispatch as:
  - "serialize" — width-1 wave (only one item), OR items touch overlapping
    files/modules, OR any doubt about independence. THIS IS THE DEFAULT.
  - "fan" — items are VERIFIED independent (disjoint files) AND mechanical
    (well-specified, low learning-potential). Only choose this when confident.
  - "serialize-preferred" — items look independent but involve learning/discovery
    where one item's findings might inform another. Surface the decision.

  Return a JSON object with:
  - waves: array of {waveNumber, items: array of issue IDs, dispatch, dispatchReason}
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
              items: { type: 'array', items: { type: 'string' } },
              dispatch: { type: 'string', enum: ['serialize', 'fan', 'serialize-preferred'] },
              dispatchReason: { type: 'string' }
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
let campaignHeld = null   // set by the oversight seam when trajectory drifts

// Execute a single campaign item (implement issue end-to-end).
// Used by both serial and parallel dispatch paths.
const executeItem = (issue, waveNumber) =>
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
      label: `wave${waveNumber}:${issue.id}`,
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

for (const wave of decomposition.waves) {
  if (campaignFailed) break

  const waveIssues = wave.items.map(id => issues.find(i => i.id === id)).filter(Boolean)

  // Dispatch decision (Axiom: default serial, fan only when verified safe).
  // Width-1 waves are always serial regardless of classification.
  const dispatch = waveIssues.length <= 1 ? 'serialize' : (wave.dispatch || 'serialize')
  const fanOut = dispatch === 'fan'

  log(`═══ Wave ${wave.waveNumber}/${decomposition.waves.length}: ${waveIssues.length} item(s), dispatch=${dispatch} ═══`)
  if (wave.dispatchReason) log(`  ${wave.dispatchReason}`)
  if (dispatch === 'serialize-preferred') {
    log(`  NOTE: items look independent but involve discovery — running serial so findings can inform later items`)
  }

  let itemResults
  if (fanOut) {
    // Verified-independent + mechanical → run concurrently
    itemResults = await parallel(waveIssues.map(issue => () => executeItem(issue, wave.waveNumber)))
  } else {
    // Default: serial. Wall-clock cost, but no risk of overlapping-file clobber.
    itemResults = []
    for (const issue of waveIssues) {
      itemResults.push(await executeItem(issue, wave.waveNumber))
    }
  }

  const waveReport = {
    waveNumber: wave.waveNumber,
    dispatch,
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
  if (campaignFailed) break

  // ── OVERSIGHT SEAM ──────────────────────────────────────────────
  // "Control flow is code; judgment is a seam." After a wave PASSES, a distinct
  // campaign-altitude judge (NOT reused from the execution agents) asks: given
  // the intent, the trajectory so far, AND prior related sessions, is it safe to
  // continue to the next wave? This is where we beat BJ — the overseer sees our
  // recall/history context, which his stateless-container design can't provide.
  //
  // Skip after the final wave (nothing to gate) and when the campaign already failed.
  const isLastWave = wave.waveNumber >= decomposition.waves.length
  if (!isLastWave) {
    const trajectory = waveResults.map(w =>
      `Wave ${w.waveNumber} (${w.dispatch}): ${w.succeeded.length} done, ${w.failed.length} failed, ${w.blocked.length} blocked` +
      `${w.succeeded.length ? ' — shipped: ' + w.succeeded.map(s => s.issueId + (s.commitMessage ? ' (' + s.commitMessage + ')' : '')).join(', ') : ''}` +
      `${w.blocked.length ? ' — blocked: ' + w.blocked.map(b => b.issueId + ': ' + (b.error || '?')).join('; ') : ''}`
    ).join('\n')

    const oversight = await agent(
      `You are the CAMPAIGN OVERSEER — a distinct campaign-altitude judge. You do
      NOT execute work; you assess whether the campaign is still on the rails.

      CAMPAIGN INTENT (what this whole batch is FOR):
      ${campaignIntent}

      PRIOR CONTEXT (relevant past sessions + repo merge history — use this to spot
      drift from what was intended or repeats of past mistakes):
      ${priorContext}

      TRAJECTORY SO FAR (waves completed):
      ${trajectory}

      REMAINING WAVES: ${decomposition.waves.length - wave.waveNumber}
      NEXT WAVE: ${decomposition.waves.length > wave.waveNumber ?
        'items ' + (decomposition.waves[wave.waveNumber]?.items || []).join(', ') : 'none'}

      Judge whether it is SAFE and SENSIBLE to continue to the next wave. Consider:
      - Is the work actually serving the stated intent, or drifting from it?
      - Do the shipped changes so far cohere, or are they pulling in different directions?
      - Do the blockers/concerns suggest the plan is wrong, not just the execution?
      - Does prior context reveal this approach already failed before?

      This is NOT a per-item review (that already happened). It's a trajectory check.
      Default to continue UNLESS you see real drift — a HOLD costs the human's
      attention, so only pull that cord when it's warranted.

      Return a JSON object with:
      - continue: boolean — safe to proceed to the next wave?
      - confidence: number 0-100 — how confident in that verdict
      - concern: string or null — the single most important concern, if any
      - recommendation: string — what the human should do if you said continue:false
      - driftFromIntent: boolean — is the work drifting from the stated intent?`,
      {
        label: `oversee:after-wave${wave.waveNumber}`,
        phase: 'Oversee',
        schema: {
          type: 'object',
          properties: {
            continue: { type: 'boolean' },
            confidence: { type: 'number' },
            concern: { type: ['string', 'null'] },
            recommendation: { type: 'string' },
            driftFromIntent: { type: 'boolean' }
          },
          required: ['continue', 'confidence', 'recommendation']
        }
      }
    )

    if (oversight) {
      waveReport.oversight = oversight
      log(`  Oversight after wave ${wave.waveNumber}: continue=${oversight.continue} (${oversight.confidence}% confident)`)
      if (oversight.concern) log(`    concern: ${oversight.concern}`)

      // HOLD conditions (a Legal Exit per Axiom 6 — this is a considered stop,
      // not "accumulated anxiety"): explicit no-continue, or confidence below floor.
      const belowFloor = oversight.confidence < confidenceFloor
      if (oversight.continue === false || belowFloor) {
        const why = oversight.continue === false
          ? 'overseer flagged: ' + (oversight.concern || 'unsafe to continue')
          : `confidence ${oversight.confidence}% below floor ${confidenceFloor}%`
        log(`  Campaign HELD after wave ${wave.waveNumber}: ${why}`)
        campaignHeld = { wave: wave.waveNumber, why, oversight }
        break
      }
    } else {
      log(`  Oversight after wave ${wave.waveNumber}: judge unavailable — continuing (fail-open on oversight)`)
    }
  }
  // ────────────────────────────────────────────────────────────────
}

phase('Report')

const totalItems = issues.length
const completedItems = waveResults.flatMap(w => w.succeeded).length
const failedItems = waveResults.flatMap(w => w.failed).length
const blockedItems = waveResults.flatMap(w => w.blocked).length

const wavesRun = waveResults.length
const heldNote = campaignHeld ? ` — HELD by oversight after wave ${campaignHeld.wave}` : ''
const summary = `Campaign: ${completedItems}/${totalItems} complete, ${failedItems} failed, ${blockedItems} blocked (${wavesRun}/${decomposition.waves.length} waves run)${heldNote}`
log(summary)

// Write evidence for the whole campaign
const allPRs = waveResults
  .flatMap(w => w.succeeded)
  .filter(r => r.prUrl)
  .map(r => r.prUrl)

// Status: held (oversight stopped us) > partial (hard fault) > complete
let campaignStatus = 'complete'
if (campaignHeld) campaignStatus = 'held'
else if (campaignFailed) campaignStatus = 'partial'

return {
  status: campaignStatus,
  summary,
  intent: campaignIntent,
  waves: decomposition.waves.length,
  wavesRun,
  topology: decomposition.topology,
  held: campaignHeld ? {
    afterWave: campaignHeld.wave,
    why: campaignHeld.why,
    recommendation: campaignHeld.oversight.recommendation,
    driftFromIntent: campaignHeld.oversight.driftFromIntent
  } : null,
  results: {
    total: totalItems,
    completed: completedItems,
    failed: failedItems,
    blocked: blockedItems
  },
  prs: allPRs,
  waveDetails: waveResults.map(w => ({
    wave: w.waveNumber,
    dispatch: w.dispatch,
    succeeded: w.succeeded.map(s => s.issueId),
    failed: w.failed.map(f => ({ id: f.issueId, error: f.error })),
    blocked: w.blocked.map(b => ({ id: b.issueId, error: b.error })),
    oversight: w.oversight ? { continue: w.oversight.continue, confidence: w.oversight.confidence, concern: w.oversight.concern } : null
  }))
}
