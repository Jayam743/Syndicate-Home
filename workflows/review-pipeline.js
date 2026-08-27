export const meta = {
  name: 'syndicate-review',
  description: 'Review pipeline: bug-finding across dimensions + omission-verification against acceptance criteria, then adversarial verify',
  whenToUse: 'When reviewing code changes (branch diff, staged changes, or specific files)',
  phases: [
    { title: 'Scope', detail: 'Derive an atomic checklist from the acceptance criteria (what SHOULD be there)' },
    { title: 'Review', detail: 'Parallel: find bugs present + closed per-item lookups for requirements absent' },
    { title: 'Verify', detail: 'Loki adversarially verifies each present-bug finding' }
  ]
}

// Review pipeline: TWO complementary tracks.
//   1. Bug-finding (present defects) — multi-dimensional review + adversarial verify
//   2. Omission-verification (absent requirements) — "invert the question": a model
//      has no internal signal for "is anything missing?", so we derive an atomic
//      checklist from the acceptance criteria (the SOURCE) and run CLOSED per-item
//      lookups against the code (the OUTPUT): "requirement X — satisfied? where?"
//      (Adapted from BJ's reseed omission-verification; placed here on review, where
//       missing-requirement misses cost more than missing-context misses.)
//
// Args expected:
//   target: string — what to review ("staged", "branch", or file paths)
//   context: string — what was changed and why
//   acceptanceCriteria: string — the requirements this change must satisfy (issue
//       acceptance criteria, devspec section, or the task statement). If omitted,
//       the omission track derives criteria from context + the change itself.
//   recallBrief / priorContext: string — prior-context brief (past sessions + merge
//       history). If absent, the recall pre-stage runs ~/.syndicate/scripts/recall.sh.
//   skipScribe: boolean — skip the Scope checklist-crafting stage (Scribe-like)
//   skipScribeReason: string — REQUIRED when skipScribe is set (deterministic gate)
//   skipRecall: boolean — skip the recall pre-stage
//   skipRecallReason: string — REQUIRED when skipRecall is set (deterministic gate)

const DIMENSIONS = [
  { key: 'correctness', prompt: 'Does the code do what it claims? Check logic, off-by-ones, wrong operators, inverted conditions.' },
  { key: 'security', prompt: 'Check for injection, auth bypass, exposed secrets, OWASP top 10, unsafe deserialization.' },
  { key: 'edge-cases', prompt: 'Null/empty inputs, boundary conditions, race conditions, concurrency issues.' },
  { key: 'integration', prompt: 'Does it break anything it touches? Check API contracts, database schemas, shared state.' }
]

const reviewTarget = args.target || 'staged changes (git diff --cached)'
const acceptanceCriteria = args.acceptanceCriteria || ''

// ── Phase: Scope — derive the atomic checklist (the "what SHOULD be here") ──
phase('Scope')

// Deterministic preconditions (issue #4): a skip must carry a reason, and recall
// must run unless an explicit, reasoned opt-out is supplied.
if (args.skipScribe && !args.skipScribeReason) {
  return { status: 'failed', stage: 'Scope', reason: 'skipScribe requires skipScribeReason' }
}
if (args.skipRecall && !args.skipRecallReason) {
  return { status: 'failed', stage: 'Scope', reason: 'skipRecall requires skipRecallReason' }
}

// STAGE: recall — ground the review in relevant past sessions + merge history.
let recallBrief = args.recallBrief || args.priorContext || ''
if (args.skipRecall) {
  log(`Recall skipped: ${args.skipRecallReason}`)
} else if (!recallBrief) {
  const recall = await agent(
    `You are running the Syndicate recall pre-stage. Shell out to the recall script
    and return its output verbatim — do NOT investigate or add your own analysis.

    Run: ~/.syndicate/scripts/recall.sh ${JSON.stringify(args.context || reviewTarget || '')}

    Return a JSON object with:
    - brief: string — the script's stdout (the context brief), "" if nothing relevant
    - matched: boolean — whether any prior session or merge matched`,
    {
      label: 'recall:prime',
      phase: 'Scope',
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

// STAGE: scribe — the Scope stage recrafts the acceptance criteria into an atomic,
// closed checklist (the review-pipeline's Scribe-role: shape the intent before work).
let checklist = null
if (args.skipScribe) {
  log(`Scribe (Scope) skipped: ${args.skipScribeReason}`)
} else {
  checklist = await agent(
  `You are Athena, building a verification checklist for a code review.

  TARGET UNDER REVIEW: ${reviewTarget}
  CONTEXT: ${args.context || 'code review requested'}
  ${recallBrief ? `PRIOR CONTEXT (past sessions + merge history):\n${recallBrief}` : ''}
  ${acceptanceCriteria
    ? `ACCEPTANCE CRITERIA (the source of truth for what this change must do):\n${acceptanceCriteria}`
    : 'NO explicit acceptance criteria were given. Derive the intended requirements from the context and the change itself — what SHOULD a correct version of this include?'}

  Break the requirements into ATOMIC checklist items — each one a single, closed,
  independently-checkable statement of something the code MUST do or have. Do not
  ask open questions. Each item must be answerable yes/no by looking at the code.

  Good items: "Rejects requests with an expired token (401)", "Persists the avatar
  URL to the user record", "Logs the failure with the request id".
  Bad items: "Handles errors well", "Is secure" (not atomic, not closed).

  Return a JSON object with:
  - items: array of {id, requirement} — the atomic checklist
  - derivedFrom: "acceptance-criteria" | "inferred-from-context"`,
  {
    label: 'athena:checklist',
    phase: 'Scope',
    schema: {
      type: 'object',
      properties: {
        items: {
          type: 'array',
          items: {
            type: 'object',
            properties: { id: { type: 'string' }, requirement: { type: 'string' } },
            required: ['id', 'requirement']
          }
        },
        derivedFrom: { type: 'string' }
      },
      required: ['items']
    }
  }
  )
}

const checklistItems = checklist ? (checklist.items || []) : []
log(`Scope: ${checklistItems.length} atomic requirement(s) to verify (${checklist ? checklist.derivedFrom : 'n/a'})`)

phase('Review')

// Two tracks run in parallel:
//   (a) bug-finding dimensions — defects PRESENT in the code
//   (b) omission checks — one closed lookup per checklist item (requirements ABSENT)
const bugThunks = DIMENSIONS.map(dim => () =>
  agent(
    `You are Athena reviewing for ${dim.key} issues.

    TARGET: ${reviewTarget}
    CONTEXT: ${args.context || 'code review requested'}

    Focus on: ${dim.prompt}

    Rules:
    - Only report issues at 80%+ confidence
    - Be specific: file, line, what's wrong, what happens
    - No style nitpicks or gold-plating suggestions

    Return a JSON object with:
    - dimension: "${dim.key}"
    - findings: array of {severity, file, line, issue, failureScenario, fix}
    - clean: boolean (true if no findings)`,
    {
      label: `athena:${dim.key}`,
      phase: 'Review',
      schema: {
        type: 'object',
        properties: {
          dimension: { type: 'string' },
          findings: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                severity: { type: 'string' },
                file: { type: 'string' },
                line: { type: 'number' },
                issue: { type: 'string' },
                failureScenario: { type: 'string' },
                fix: { type: 'string' }
              }
            }
          },
          clean: { type: 'boolean' }
        },
        required: ['dimension', 'findings', 'clean']
      }
    }
  )
)

// Omission track: ONE closed lookup per checklist item. This is the "invert the
// question" trick — instead of "is anything missing?" (unanswerable), we ask
// "is THIS specific requirement satisfied, and where?" for each atomic item.
const omissionThunks = checklistItems.map(item => () =>
  agent(
    `You are Athena performing a CLOSED requirement check. Answer ONLY about this
    one requirement — do not hunt for other issues.

    TARGET: ${reviewTarget}
    REQUIREMENT [${item.id}]: ${item.requirement}

    Look at the code and determine: is THIS requirement satisfied? Find where it is
    implemented (file:line) or confirm it is absent. Be literal — "partially" counts
    as not satisfied; say what's missing.

    Return a JSON object with:
    - id: "${item.id}"
    - requirement: ${JSON.stringify(item.requirement)}
    - satisfied: "yes" | "no" | "partial"
    - evidence: string — file:line where satisfied, or what's missing if no/partial`,
    {
      label: `athena:omission:${item.id}`,
      phase: 'Review',
      schema: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          requirement: { type: 'string' },
          satisfied: { type: 'string', enum: ['yes', 'no', 'partial'] },
          evidence: { type: 'string' }
        },
        required: ['id', 'satisfied', 'evidence']
      }
    }
  )
)

const allResults = await parallel([...bugThunks, ...omissionThunks])
const reviews = allResults.slice(0, bugThunks.length)
const omissionResults = allResults.slice(bugThunks.length).filter(Boolean)

// Unmet requirements become findings too (severity: the requirement is a miss).
const omissions = omissionResults
  .filter(o => o.satisfied !== 'yes')
  .map(o => ({
    severity: o.satisfied === 'no' ? 'high' : 'medium',
    kind: 'omission',
    requirement: o.requirement,
    satisfied: o.satisfied,
    evidence: o.evidence
  }))

const allFindings = reviews
  .filter(Boolean)
  .flatMap(r => r.findings || [])

log(`Omission check: ${omissionResults.filter(o => o.satisfied === 'yes').length}/${omissionResults.length} requirements satisfied, ${omissions.length} unmet`)

// Truly clean only if BOTH tracks are clean (no bugs present AND no requirements absent)
if (allFindings.length === 0 && omissions.length === 0) {
  log('Athena: Clean — no bugs found and all requirements satisfied.')
  return {
    status: 'clean',
    findings: [],
    omissions: [],
    requirementsChecked: omissionResults.length,
    verified: []
  }
}

// If there are no present-bugs to adversarially verify, skip the Verify phase but
// STILL report the omissions (unmet requirements are already closed-verified).
if (allFindings.length === 0) {
  log(`No bugs present, but ${omissions.length} requirement(s) unmet — reporting omissions.`)
  return {
    status: 'findings',
    totalFound: 0,
    totalConfirmed: 0,
    totalRefuted: 0,
    findings: [],
    omissions,
    requirementsChecked: omissionResults.length
  }
}

log(`Athena found ${allFindings.length} issue(s) across ${reviews.filter(r => r && !r.clean).length} dimension(s)`)

phase('Verify')

const verified = await parallel(
  allFindings.map(finding => () =>
    agent(
      `You are Loki. Adversarially verify this finding — try to REFUTE it.

      FINDING:
      - File: ${finding.file}
      - Line: ${finding.line}
      - Issue: ${finding.issue}
      - Failure scenario: ${finding.failureScenario}
      - Suggested fix: ${finding.fix}

      Your job: prove this finding is WRONG. Read the actual code.
      - Is the code actually vulnerable/broken as claimed?
      - Does the failure scenario actually occur?
      - Is there existing protection the reviewer missed?
      - Is the severity correct?

      Default to refuted=true if you're uncertain. Only confirm real bugs.

      Return a JSON object with:
      - refuted: boolean (true if you can disprove the finding)
      - reason: string (why it's real or why it's false)
      - adjustedSeverity: string or null (if severity should change)`,
      {
        label: `loki:verify:${finding.file}`,
        phase: 'Verify',
        schema: {
          type: 'object',
          properties: {
            refuted: { type: 'boolean' },
            reason: { type: 'string' },
            adjustedSeverity: { type: ['string', 'null'] }
          },
          required: ['refuted', 'reason']
        }
      }
    )
  )
)

const confirmedFindings = allFindings
  .map((finding, i) => {
    const verdict = verified[i]
    if (!verdict || verdict.refuted) return null
    return {
      ...finding,
      severity: verdict.adjustedSeverity || finding.severity,
      verificationReason: verdict.reason
    }
  })
  .filter(Boolean)

log(`Verified: ${confirmedFindings.length}/${allFindings.length} findings confirmed (${allFindings.length - confirmedFindings.length} refuted by Loki)`)

return {
  // "clean" only if no confirmed bugs AND no unmet requirements
  status: (confirmedFindings.length > 0 || omissions.length > 0) ? 'findings' : 'clean',
  totalFound: allFindings.length,
  totalConfirmed: confirmedFindings.length,
  totalRefuted: allFindings.length - confirmedFindings.length,
  findings: confirmedFindings,
  omissions,
  requirementsChecked: omissionResults.length
}
