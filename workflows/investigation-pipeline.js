export const meta = {
  name: 'syndicate-investigation',
  description: 'Investigation pipeline: Specter diagnoses → Loki challenges → User picks → Forge fixes',
  whenToUse: 'When something is broken and the root cause is unknown — "why is X failing?"',
  phases: [
    { title: 'Investigate', detail: 'Specter observes, hypothesizes, and tests' },
    { title: 'Challenge', detail: 'Loki stress-tests the diagnosis' },
    { title: 'Present', detail: 'Options presented to user (pipeline pauses here)' }
  ]
}

// Investigation pipeline: diagnosis flow
// Specter observes → forms hypotheses → tests → Loki argues → present options
//
// SYNDICATE-NO-SCRIBE: investigation recrafts via Specter's own framing; routing-recraft is a main-loop Step 0.5 concern
//
// Args expected:
//   problem: string — what's broken / what the user asked
//   context: string — relevant system info, logs, paths
//   recallBrief / priorContext: string — prior-context brief (past investigations +
//       merge history). If absent, the recall pre-stage runs ~/.syndicate/scripts/recall.sh.
//   skipRecall: boolean — skip the recall pre-stage
//   skipRecallReason: string — REQUIRED when skipRecall is set (deterministic gate)
//   autoFix: boolean — if true, auto-pick recommended option and fix (godspeed mode)

phase('Investigate')

// Deterministic precondition (issue #4): recall runs unless a reasoned opt-out is given.
if (args.skipRecall && !args.skipRecallReason) {
  return { status: 'failed', stage: 'Investigate', reason: 'skipRecall requires skipRecallReason' }
}

// STAGE: recall — check what we already know before diagnosing from zero. This
// REPLACES Specter's old in-prompt "check memory first" step, so recall runs once.
let recallBrief = args.recallBrief || args.priorContext || ''
if (args.skipRecall) {
  log(`Recall skipped: ${args.skipRecallReason}`)
} else if (!recallBrief) {
  const recall = await agent(
    `You are running the Syndicate recall pre-stage. Shell out to the recall script
    and return its output verbatim — do NOT investigate or add your own analysis.

    Run: ~/.syndicate/scripts/recall.sh ${JSON.stringify(args.problem || '')}

    Return a JSON object with:
    - brief: string — the script's stdout (the context brief), "" if nothing relevant
    - matched: boolean — whether any prior session or merge matched`,
    {
      label: 'recall:prime',
      phase: 'Investigate',
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

const investigation = await agent(
  `You are Specter, the investigator. Something is broken and you need to find out why.

  PROBLEM: ${args.problem}
  CONTEXT: ${args.context || 'none provided'}
  ${recallBrief ? `PRIOR CONTEXT (past investigations + merge history — already recalled for you):\n${recallBrief}\n  If a prior investigation matches, START from its fix and verify it applies here instead of re-diagnosing from zero. Report the match in priorMatch.` : ''}

  Follow your investigation protocol:
  1. OBSERVE — gather symptoms, check logs, config, recent changes (READ-ONLY)
  2. HYPOTHESIZE — form 2-4 theories, rank by likelihood
  3. TEST — minimal test for each hypothesis, eliminate dead ends fast

  Return a JSON object with:
  - priorMatch: string or null — a matching past investigation (slug + its fix) if memory had one
  - symptoms: array of observed symptoms
  - hypotheses: array of {theory, likelihood, evidence_for, evidence_against, tested, result}
  - rootCause: string — what's actually wrong (null if inconclusive)
  - confidence: number 0-100 — how sure are you
  - options: array of {label, description, pros, cons, effort, recommended}
  - deadEnds: array of eliminated theories`,
  {
    label: 'specter:investigate',
    phase: 'Investigate',
    schema: {
      type: 'object',
      properties: {
        priorMatch: { type: ['string', 'null'] },
        symptoms: { type: 'array', items: { type: 'string' } },
        hypotheses: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              theory: { type: 'string' },
              likelihood: { type: 'string' },
              evidence_for: { type: 'string' },
              evidence_against: { type: 'string' },
              tested: { type: 'boolean' },
              result: { type: 'string' }
            }
          }
        },
        rootCause: { type: ['string', 'null'] },
        confidence: { type: 'number' },
        options: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              label: { type: 'string' },
              description: { type: 'string' },
              pros: { type: 'string' },
              cons: { type: 'string' },
              effort: { type: 'string' },
              recommended: { type: 'boolean' }
            }
          }
        },
        deadEnds: { type: 'array', items: { type: 'string' } }
      },
      required: ['symptoms', 'hypotheses', 'rootCause', 'confidence', 'options']
    }
  }
)

if (!investigation) {
  log('Specter failed — investigation could not complete')
  return { status: 'failed', stage: 'Investigate', reason: 'Specter returned null' }
}

log(`Specter: root cause identified (${investigation.confidence}% confidence)`)
log(`  → ${investigation.rootCause || 'inconclusive'}`)
log(`  → ${investigation.options.length} option(s), ${investigation.deadEnds ? investigation.deadEnds.length : 0} dead end(s) eliminated`)

phase('Challenge')

const challenge = await agent(
  `You are Loki, the devil's advocate. Specter just completed an investigation.

  ROOT CAUSE (${investigation.confidence}% confidence): ${investigation.rootCause}

  HYPOTHESES TESTED:
  ${investigation.hypotheses.map(h => `- ${h.theory} → ${h.result}`).join('\n')}

  PROPOSED OPTIONS:
  ${investigation.options.map(o => `- ${o.label}${o.recommended ? ' [RECOMMENDED]' : ''}: ${o.description}`).join('\n')}

  Your job: challenge this diagnosis.
  - Is the root cause actually correct, or is it a symptom of something deeper?
  - Did Specter miss any angles?
  - Are the proposed fixes actually safe?
  - What could go wrong with the recommended option?

  Return a JSON object with:
  - agrees: boolean — do you agree with the diagnosis?
  - challenges: array of {point, severity, response_needed}
  - missedAngles: array of strings (things Specter didn't check)
  - riskAssessment: string — overall risk of the recommended option
  - verdict: string — "solid", "has_gaps", or "flawed"`,
  {
    label: 'loki:challenge',
    phase: 'Challenge',
    schema: {
      type: 'object',
      properties: {
        agrees: { type: 'boolean' },
        challenges: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              point: { type: 'string' },
              severity: { type: 'string' },
              response_needed: { type: 'boolean' }
            }
          }
        },
        missedAngles: { type: 'array', items: { type: 'string' } },
        riskAssessment: { type: 'string' },
        verdict: { type: 'string' }
      },
      required: ['agrees', 'challenges', 'verdict']
    }
  }
)

if (challenge) {
  log(`Loki verdict: ${challenge.verdict}`)
  if (challenge.challenges.length > 0) {
    log(`  → ${challenge.challenges.length} challenge(s) raised`)
  }
}

phase('Present')

return {
  status: 'awaiting_decision',
  investigation: {
    rootCause: investigation.rootCause,
    confidence: investigation.confidence,
    symptoms: investigation.symptoms,
    deadEnds: investigation.deadEnds
  },
  options: investigation.options,
  lokiVerdict: challenge ? challenge.verdict : 'not_available',
  lokiChallenges: challenge ? challenge.challenges : [],
  lokiRiskAssessment: challenge ? challenge.riskAssessment : 'not assessed',
  missedAngles: challenge ? challenge.missedAngles : []
}
