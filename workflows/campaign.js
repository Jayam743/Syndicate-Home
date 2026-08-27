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
// SYNDICATE-NO-SCRIBE: campaign has no literal Scribe stage — decomposition is Odin's job and routing-recraft is a main-loop Step 0.5 concern
//
// Args expected:
//   issues: array of {id, title, description, dependencies, paths?: string[], mechanical?: boolean} — the work items
//           paths[]/mechanical feed the deterministic fan-eligibility predicate (issue #8, wired in the Execute stage).
//   repo: string — target repository path
//   branch: string — base branch to work from
//   autoMerge: boolean — auto-merge small PRs (requires all gates green)
//   maxWaves: number — safety cap on wave count (default 5)
//   maxFanWidth: number — max items a wave may fan in parallel (default 4).
//           Feeds the deterministic fan-eligibility predicate; waves wider than this serialize.
//   intent: string — the campaign's overall goal (what the whole batch is FOR).
//           Used by the oversight seam to judge trajectory drift.
//   priorContext: string — recall brief (relevant past sessions + merge history).
//           Odin fills this from ~/.syndicate/scripts/recall.sh so oversight judges against
//           history, not just this run. This is what BJ's stateless design can't do.
//   skipRecall: boolean — proceed without a recall brief (oversight judges this run only)
//   skipRecallReason: string — REQUIRED when skipRecall is set (deterministic gate)
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

// ===== BEGIN inlined fan-eligibility (KEEP IN SYNC with scripts/lib/fan-eligibility.js) =====
// The Workflow sandbox has NO require/import/fs, so the tested predicate cannot be
// imported here — it is copied BYTE-IDENTICALLY from scripts/lib/fan-eligibility.js
// (the region from `const GLOB_CHARS_RE` through the `fanEligibility` closing brace).
// scripts/ci/validate.sh diffs this block against that source and FAILS on drift.
// DO NOT edit the logic here; edit the source file and re-inline.
const GLOB_CHARS_RE = /[*?[\]]/;

function isGlobSegment(seg) {
  return GLOB_CHARS_RE.test(seg);
}

// -----------------------------------------------------------------------------
// normalizePath — canonicalize a declared path so comparisons are stable.
//   - POSIX separators (backslashes -> '/')
//   - collapse duplicate '/' into one
//   - strip leading './' (repeatedly)
//   - strip trailing '/'
// Null/undefined/non-string inputs collapse to '' so they get caught by the
// "too broad" gate below (serialize on garbage input — never fan).
// -----------------------------------------------------------------------------
function normalizePath(p) {
  let s = p == null ? '' : String(p);
  s = s.replace(/\\/g, '/'); // POSIX separators
  s = s.replace(/\/+/g, '/'); // collapse duplicate slashes
  while (s.startsWith('./')) {
    s = s.slice(2);
  }
  if (s.length > 1 && s.endsWith('/')) {
    s = s.slice(0, -1);
  }
  return s;
}

// -----------------------------------------------------------------------------
// pathsConflict — do two NORMALIZED paths possibly touch a common file?
//
// Compared by PATH SEGMENTS (never raw string prefix), so 'src/foo' does not
// falsely conflict with 'src/foo-bar', but 'src/foo' does conflict with
// 'src/foo/bar.js' and with 'src'.
//
// File-vs-directory: a path whose last segment carries a literal extension
// (a dot, no glob chars) reads as a FILE; otherwise it reads as a DIRECTORY
// prefix. We compute nothing special from this because the segment-nesting
// rule below is STRICTLY MORE CONSERVATIVE than any file/dir distinction:
//   - a directory prefix conflicts with everything nested under it, and
//   - treating a "file" that is nonetheless a strict prefix of a longer path
//     as disjoint would be an optimistic assumption — forbidden by the
//     bias-to-serialize doctrine. So any segment-nesting => CONFLICT.
// The file/dir heuristic can therefore only ever ADD conflicts, never remove
// one, so it collapses into the nesting rule and needs no separate branch.
//
// Algorithm (walk the shared segment depth):
//   * if either segment at depth i is a glob   -> cannot prove they differ -> CONFLICT
//   * if both are literal and DIFFER           -> subtrees provably disjoint -> no conflict
//   * if both are literal and EQUAL            -> keep walking
//   * fell off the end (one is a prefix of the
//     other, or they are identical)            -> nested/equal -> CONFLICT
// -----------------------------------------------------------------------------
function pathsConflict(a, b) {
  const segsA = a.split('/');
  const segsB = b.split('/');
  const depth = Math.min(segsA.length, segsB.length);

  for (let i = 0; i < depth; i++) {
    const sa = segsA[i];
    const sb = segsB[i];
    if (isGlobSegment(sa) || isGlobSegment(sb)) {
      return true; // unsure -> conflict
    }
    if (sa !== sb) {
      return false; // concrete divergence -> disjoint subtrees
    }
  }
  // Identical, or one is a segment-prefix of the other -> conflict.
  return true;
}

// -----------------------------------------------------------------------------
// fanEligibility — THE predicate. Returns { eligible, reason }.
// See rule numbers inline; every "no" path returns a specific reason string.
// -----------------------------------------------------------------------------
function fanEligibility(items, maxFanWidth = 4) {
  const list = Array.isArray(items) ? items : [];
  const width = list.length;

  // Rule 1: nothing to parallelize.
  if (width <= 1) {
    return { eligible: false, reason: 'width<=1' };
  }

  // Rule 2: too wide. NO batching — Athena's explicit call is to serialize.
  if (width > maxFanWidth) {
    return {
      eligible: false,
      reason: `width ${width} > maxFanWidth ${maxFanWidth}`,
    };
  }

  // Rule 3: every item must be explicitly mechanical. Missing/undefined
  // mechanical is treated as NOT mechanical (=== true is the only pass).
  for (const item of list) {
    if (!item || item.mechanical !== true) {
      const id = item ? item.id : undefined;
      return { eligible: false, reason: `item ${id} not mechanical` };
    }
  }

  // Rule 4: every item must declare a non-empty paths[].
  for (const item of list) {
    if (!Array.isArray(item.paths) || item.paths.length === 0) {
      return { eligible: false, reason: `item ${item.id} declares no paths[]` };
    }
  }

  // Rules 5 + 6: normalize every path, then reject anything too broad to prove
  // disjoint. A repo-wide / leading-glob path effectively touches everything.
  const normalizedByItem = list.map((item) => ({
    id: item.id,
    paths: item.paths.map(normalizePath),
  }));

  for (const item of normalizedByItem) {
    for (const p of item.paths) {
      const firstSeg = p.split('/')[0];
      if (
        p === '' ||
        p === '.' ||
        p === '*' ||
        p === '**' ||
        p.startsWith('**') ||
        firstSeg === '*' ||
        firstSeg === '**'
      ) {
        return {
          eligible: false,
          reason: `item ${item.id} path '${p}' is too broad to prove disjoint`,
        };
      }
    }
  }

  // Rule 7: pairwise disjointness across ALL items (every pair, every
  // path-vs-path). conflict is symmetric, so i<j covers both directions.
  for (let i = 0; i < normalizedByItem.length; i++) {
    for (let j = i + 1; j < normalizedByItem.length; j++) {
      const A = normalizedByItem[i];
      const B = normalizedByItem[j];
      for (const pa of A.paths) {
        for (const pb of B.paths) {
          if (pathsConflict(pa, pb)) {
            return {
              eligible: false,
              reason: `item ${A.id} path '${pa}' overlaps item ${B.id} path '${pb}'`,
            };
          }
        }
      }
    }
  }

  // Rule 8: only now is a fan provably safe.
  return {
    eligible: true,
    reason: `width ${width}, all mechanical, disjoint paths`,
  };
}
// ===== END inlined fan-eligibility =====

phase('Decompose')

const issues = args.issues || []
const maxWaves = args.maxWaves || 5
const campaignIntent = args.intent || '(intent not stated — infer from the issue set)'
const confidenceFloor = args.overseeConfidenceFloor || 50

// Deterministic precondition (issue #4): if recall is skipped it must carry a reason.
if (args.skipRecall && !args.skipRecallReason) {
  return { status: 'failed', stage: 'Decompose', reason: 'skipRecall requires skipRecallReason' }
}

// STAGE: recall — the recall brief (past sessions + merge history) is supplied by the
// main loop via args.priorContext and consumed by the oversight seam below. If it is
// absent, the campaign proceeds only when an explicit, reasoned opt-out is given.
let priorContext = args.priorContext || ''
if (!priorContext) {
  if (args.skipRecall) {
    log(`Recall skipped: ${args.skipRecallReason}`)
  } else {
    log('Recall: no prior context supplied — oversight judges this run only')
  }
  priorContext = '(no prior context supplied)'
}

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
// Used by both serial and parallel dispatch paths. When opts.isolated is set the
// item runs in its OWN fresh git worktree (isolation:'worktree'), so #30's
// per-worktree test sentinel gates that item's push independently.
const executeItem = (issue, waveNumber, opts = {}) =>
  agent(
    `You are executing a campaign item. Implement this issue end-to-end.

    ISSUE: [${issue.id}] ${issue.title}
    DESCRIPTION: ${issue.description || 'see title'}
    REPO: ${args.repo || 'current directory'}
    BASE BRANCH: ${args.branch || 'current branch'}
${opts.isolated ? `
    ISOLATION CONTRACT (you are running in your OWN dedicated git worktree):
    - You MUST work only inside this worktree; do NOT touch the shared checkout.
    - Run the FULL build → test → push flow so the per-worktree test sentinel
      (#30) gates your push — do not push if tests did not pass.
    - Do NOT delete or clean up your worktree; the campaign removes it only after
      your push succeeds.
    - Report the absolute path of your worktree in the "worktree" field. If you
      cannot confirm you are in a dedicated worktree, STOP and return status
      "failed" with error "isolation not confirmed" (fail closed).
` : ''}
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
    - worktree: string or null (absolute path of the isolated worktree, if any)
    - error: string or null (if failed/blocked)`,
    {
      label: `wave${waveNumber}:${issue.id}`,
      phase: 'Execute',
      ...(opts.isolated ? { isolation: 'worktree' } : {}),
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
          worktree: { type: ['string', 'null'] },
          error: { type: ['string', 'null'] }
        },
        required: ['issueId', 'status']
      }
    }
  )

// ── Worktree-isolation capability probe (issue #8, sub-build 3) ──────────────
// FAIL-CLOSED CONTRACT: a wave may fan ONLY when we can PROVE each item runs in
// its OWN fresh git worktree — the #30 per-worktree test sentinel depends on that
// isolation, and a wrong "fan" can corrupt shared state / ship untested code.
// This is a REAL runtime check, not an assumption: we ask the runtime whether it
// advertises per-item worktree isolation (the mechanism used by executeItem's
// agent({ isolation: 'worktree' }) call). `typeof` on an undeclared identifier is
// safe (yields 'undefined', never throws), so the probe degrades cleanly to
// serialize on any runtime that does not expose the capability.
// TODO(#8): until the harness advertises `capabilities.worktreeIsolation === true`,
// this resolves false and the campaign safely degrades to recommend-and-serialize.
const worktreeIsolationAvailable = (() => {
  try {
    const caps =
      (typeof capabilities !== 'undefined' && capabilities) ||
      (typeof runtime !== 'undefined' && runtime && runtime.capabilities) ||
      null
    return !!(caps && caps.worktreeIsolation === true)
  } catch (_e) {
    return false
  }
})()
log(`Worktree isolation capability: ${worktreeIsolationAvailable ? 'available (fan permitted when eligible)' : 'UNAVAILABLE → fan disabled, serialize (fail-closed)'}`)
// If isolation lights up but the cleanup helper isn't exposed, isolated worktrees
// would accumulate on disk. Warn once so the operational leak is visible, not silent.
if (worktreeIsolationAvailable && typeof removeWorktree !== 'function') {
  log('WARN: worktree isolation available but removeWorktree() not exposed — isolated worktrees will not be auto-cleaned')
}

for (const wave of decomposition.waves) {
  if (campaignFailed) break

  const waveIssues = wave.items.map(id => issues.find(i => i.id === id)).filter(Boolean)

  // Dispatch decision. The deterministic fan-eligibility predicate (issue #8) is the
  // AUTHORITY on whether this wave may fan; the LLM's wave.dispatch classification is
  // informational only. Bias is asymmetric: a wrong "fan" can corrupt shared state or
  // ship untested code, a wrong "serialize" only costs wall-clock — so we serialize on
  // any doubt. Width-1 waves resolve to serialize inside fanEligibility (Rule 1).
  const maxFanWidth = args.maxFanWidth || 4
  const elig = fanEligibility(waveIssues, maxFanWidth)

  // REQUIRED instrumentation (Athena's silent-never-fan concern): always log the
  // decision + reason, so a wave that COULD fan but doesn't shows exactly why.
  log(`Wave ${wave.waveNumber} fan-eligibility: ${elig.eligible ? 'ELIGIBLE' : 'serialize'} — ${elig.reason}`)

  // FAIL-CLOSED: never fan without PROVABLE per-item worktree isolation.
  const fanOut = elig.eligible && worktreeIsolationAvailable
  if (elig.eligible && !worktreeIsolationAvailable) {
    log('  fan-eligible but worktree isolation unavailable → serializing (fail-closed)')
  }
  const dispatch = fanOut ? 'fan' : 'serialize'

  log(`═══ Wave ${wave.waveNumber}/${decomposition.waves.length}: ${waveIssues.length} item(s), dispatch=${dispatch} ═══`)
  if (wave.dispatchReason) log(`  classifier note: ${wave.dispatchReason}`)

  let itemResults
  if (fanOut) {
    // CONTRACT ASSERTION (encoded, not commented): the #30 sentinel contract requires
    // each fanned item to run in its OWN isolated worktree. We only reach this branch
    // when worktreeIsolationAvailable proved true; re-assert here to abort the fan and
    // serialize if that ever fails to hold.
    if (!worktreeIsolationAvailable) {
      log('  isolation contract violated at dispatch — aborting fan, serializing (fail-closed)')
      itemResults = []
      for (const issue of waveIssues) {
        itemResults.push(await executeItem(issue, wave.waveNumber))
      }
    } else {
      // Each item runs in its OWN fresh git worktree, through the full build→test→push
      // flow so #30's per-worktree test sentinel gates that item's push.
      itemResults = await parallel(waveIssues.map(issue => () => executeItem(issue, wave.waveNumber, { isolated: true })))

      // POST-CONDITION (fail closed): an item may only count as fanned-complete if it
      // PROVES it ran in an isolated worktree. Anything that cannot prove isolation is
      // downgraded to failed so its worktree is preserved (below) for inspection.
      for (const r of itemResults) {
        if (r && r.status === 'complete' && !r.worktree) {
          log(`  item ${r.issueId} claimed complete without proving worktree isolation → marking failed`)
          r.status = 'failed'
          r.error = 'isolation not proven (no worktree reported)'
        }
      }

      // CLEANUP (push-then-clean): remove a worktree ONLY after the item's push
      // succeeded. FAILED/blocked items KEEP their worktree — never --force a dirty
      // tree that may hold un-pushed commits — and we log the path for inspection.
      for (const r of itemResults) {
        if (!r || !r.worktree) continue
        const pushed = r.status === 'complete' && r.testsPassed === true && !!r.prUrl
        if (pushed) {
          if (typeof removeWorktree === 'function') removeWorktree(r.worktree)
          log(`  cleaned worktree for ${r.issueId} (push succeeded): ${r.worktree}`)
        } else {
          log(`  KEEPING worktree for ${r.issueId} (not pushed) for inspection → ${r.worktree}`)
        }
      }
    }
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
