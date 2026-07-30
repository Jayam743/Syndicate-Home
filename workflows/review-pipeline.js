export const meta = {
  name: 'syndicate-review',
  description: 'Review pipeline: Athena reviews across dimensions, Loki verifies findings',
  whenToUse: 'When reviewing code changes (branch diff, staged changes, or specific files)',
  phases: [
    { title: 'Review', detail: 'Athena reviews across 5 dimensions' },
    { title: 'Verify', detail: 'Loki adversarially verifies each finding' }
  ]
}

// Review pipeline: multi-dimensional review with adversarial verification
//
// Args expected:
//   target: string — what to review ("staged", "branch", or file paths)
//   context: string — what was changed and why

const DIMENSIONS = [
  { key: 'correctness', prompt: 'Does the code do what it claims? Check logic, off-by-ones, wrong operators, inverted conditions.' },
  { key: 'security', prompt: 'Check for injection, auth bypass, exposed secrets, OWASP top 10, unsafe deserialization.' },
  { key: 'edge-cases', prompt: 'Null/empty inputs, boundary conditions, race conditions, concurrency issues.' },
  { key: 'integration', prompt: 'Does it break anything it touches? Check API contracts, database schemas, shared state.' }
]

phase('Review')

const reviewTarget = args.target || 'staged changes (git diff --cached)'

const reviews = await parallel(
  DIMENSIONS.map(dim => () =>
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
)

const allFindings = reviews
  .filter(Boolean)
  .flatMap(r => r.findings || [])

if (allFindings.length === 0) {
  log('Athena: Clean across all dimensions. No findings.')
  return { status: 'clean', findings: [], verified: [] }
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
  status: confirmedFindings.length > 0 ? 'findings' : 'clean',
  totalFound: allFindings.length,
  totalConfirmed: confirmedFindings.length,
  totalRefuted: allFindings.length - confirmedFindings.length,
  findings: confirmedFindings
}
