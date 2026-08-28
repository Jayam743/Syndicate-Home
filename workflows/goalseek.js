export const meta = {
  name: 'syndicate-goalseek',
  description: 'Goal-seeking loop for open-ended work: probe → judge sufficiency → steer → journal, until sufficient or escalation cord fires',
  whenToUse: 'When the goal is clear but the plan is NOT — research, exploration, "figure out X", "get this working", open-ended debugging. Use syndicate-campaign instead when you already have a known list of issues/steps.',
  phases: [
    { title: 'Seek', detail: 'Iterate: probe → judge sufficiency → steer, journaling each round' },
    { title: 'Land', detail: 'Emit the result (answer, plan, or artifact) or escalate' }
  ]
}

// Goal-seeking workflow: the OTHER execution mode (BJ's executor-model insight).
//
// Two fundamentally different modes:
//   - PLAN-EXECUTION (syndicate-campaign): run a known DAG to completeness.
//     Terminates on completeness.
//   - GOAL-SEEKING (this): probe→judge→steer→journal loop toward sufficiency.
//     Terminates on a judgment call ("good enough") or the escalation cord.
//
// Conflating these two is a design error. A goal without a plan should NOT be
// forced into a wave decomposition — it should be probed iteratively until a
// judge says "sufficient", at which point it may HAND OFF to plan-execution.
//
// SYNDICATE-NO-SCRIBE: goal-seeking frames each probe via its own steering; routing-recraft is a main-loop Step 0.5 concern
//
// Args expected:
//   goal: string — what "done" looks like (the target, not the steps)
//   context: string — starting knowledge, constraints, where to look
//   recallBrief / priorContext: string — prior-context brief (past sessions + merge
//       history). If absent, the recall pre-stage runs ~/.syndicate/scripts/recall.sh.
//   skipRecall: boolean — skip the recall pre-stage
//   skipRecallReason: string — REQUIRED when skipRecall is set (deterministic gate)
//   maxRounds: number — hard cap on probe rounds (default 6)
//   agentType: string — which specialist probes ("specter" for investigation,
//              "forge" for build-toward-working, "Explore" for read-only research/
//              study/mapping a codebase, default general reasoning)
//   emit: "answer" | "plan" | "artifact" — what to produce when sufficient
//
// RESEARCH tasks (read-only "analyze/study/map X") route here with
// agentType:"Explore" — each probe is an Explore search, the judge decides when
// enough has been gathered, and emit:"answer" synthesizes the findings.

const goal = args.goal
const maxRounds = args.maxRounds || 6
const emit = args.emit || 'answer'

if (!goal) {
  return { status: 'failed', reason: 'No goal provided' }
}

phase('Seek')

// Deterministic precondition (issue #4): recall runs unless a reasoned opt-out is given.
if (args.skipRecall && !args.skipRecallReason) {
  return { status: 'failed', stage: 'Seek', reason: 'skipRecall requires skipRecallReason' }
}

// STAGE: recall — ground the first probe in relevant past sessions + merge history.
let recallBrief = args.recallBrief || args.priorContext || ''
if (args.skipRecall) {
  log(`Recall skipped: ${args.skipRecallReason}`)
} else if (!recallBrief) {
  const recall = await agent(
    `You are running the Syndicate recall pre-stage. Shell out to the recall script
    and return its output verbatim — do NOT investigate or add your own analysis.

    Run: ~/.syndicate/scripts/recall.sh ${JSON.stringify(goal || '')}

    Return a JSON object with:
    - brief: string — the script's stdout (the context brief), "" if nothing relevant
    - matched: boolean — whether any prior session or merge matched`,
    {
      label: 'recall:prime',
      phase: 'Seek',
      model: 'us.anthropic.claude-haiku-4-5-20251001-v1:0', // cost-tier (#22): mechanical shell-out
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

const journal = []       // append-only record of every round
let sufficient = false
let round = 0
let steer = [args.context, recallBrief ? `Prior context (past sessions + merge history):\n${recallBrief}` : '']
  .filter(Boolean).join('\n\n') || 'Start from scratch.'
let lastConfidence = 0
let stalledRounds = 0    // rounds with no meaningful progress (escalation cord)

log(`Goal-seek: "${goal}" (max ${maxRounds} rounds, emit=${emit})`)

while (!sufficient && round < maxRounds) {
  round++

  // --- PROBE: make one bounded attempt toward the goal ---
  const probe = await agent(
    `You are probing toward a goal. This is round ${round} of at most ${maxRounds}.

    GOAL (what "done" looks like): ${goal}

    STEERING (what to focus on this round): ${steer}

    ${journal.length > 0 ? `WHAT'S BEEN LEARNED SO FAR:\n${journal.map((j, i) => `Round ${i + 1}: ${j.finding}`).join('\n')}` : ''}

    Make ONE bounded probe toward the goal. Investigate, try, read, or build —
    whatever moves you closer. Do NOT try to finish everything; just advance one step.

    Return a JSON object with:
    - finding: string — what you learned or produced this round
    - progress: string — how this moved toward the goal
    - blockers: array of strings — what's in the way (empty if none)
    - artifacts: array of strings — files/outputs produced (empty if none)`,
    {
      label: `probe:round${round}`,
      phase: 'Seek',
      agentType: args.agentType,
      schema: {
        type: 'object',
        properties: {
          finding: { type: 'string' },
          progress: { type: 'string' },
          blockers: { type: 'array', items: { type: 'string' } },
          artifacts: { type: 'array', items: { type: 'string' } }
        },
        required: ['finding', 'progress']
      }
    }
  )

  if (!probe) {
    log(`Round ${round}: probe failed (agent returned null)`)
    stalledRounds++
    journal.push({ round, finding: '(probe failed)', progress: 'none', judged: null })
    if (stalledRounds >= 2) {
      log('Escalation cord: 2 consecutive failed probes')
      break
    }
    continue
  }

  // --- JUDGE: is the goal now sufficiently met? ---
  const judgment = await agent(
    `You are the sufficiency judge. Decide if the goal is MET WELL ENOUGH to stop.

    GOAL: ${goal}

    LATEST PROBE:
    - Finding: ${probe.finding}
    - Progress: ${probe.progress}
    - Blockers: ${(probe.blockers || []).join('; ') || 'none'}

    CUMULATIVE JOURNAL:
    ${journal.map((j, i) => `Round ${i + 1}: ${j.finding} (progress: ${j.progress})`).join('\n') || '(this is round 1)'}

    Judge sufficiency — NOT perfection. The question is "is this good enough to stop
    and emit a result?", not "is this flawless?". Also assess whether we're still
    making meaningful progress or hitting diminishing returns.

    Return a JSON object with:
    - sufficient: boolean — is the goal met well enough to stop?
    - confidence: number 0-100 — how sure are you
    - reasoning: string — why sufficient or why not
    - diminishingReturns: boolean — are recent rounds adding little?
    - nextSteer: string — if not sufficient, what should the next probe focus on?`,
    {
      label: `judge:round${round}`,
      phase: 'Seek',
      schema: {
        type: 'object',
        properties: {
          sufficient: { type: 'boolean' },
          confidence: { type: 'number' },
          reasoning: { type: 'string' },
          diminishingReturns: { type: 'boolean' },
          nextSteer: { type: 'string' }
        },
        required: ['sufficient', 'confidence', 'reasoning']
      }
    }
  )

  journal.push({
    round,
    finding: probe.finding,
    progress: probe.progress,
    blockers: probe.blockers || [],
    artifacts: probe.artifacts || [],
    judged: judgment ? { sufficient: judgment.sufficient, confidence: judgment.confidence } : null
  })

  if (!judgment) {
    log(`Round ${round}: judge failed — continuing`)
    continue
  }

  log(`Round ${round}: ${judgment.sufficient ? 'SUFFICIENT' : 'not yet'} (${judgment.confidence}% confident)`)

  // --- ESCALATION CORD: diminishing returns or flat confidence ---
  if (judgment.diminishingReturns || judgment.confidence <= lastConfidence) {
    stalledRounds++
    if (stalledRounds >= 2 && !judgment.sufficient) {
      log(`Escalation cord fired: diminishing returns over ${stalledRounds} rounds`)
      break
    }
  } else {
    stalledRounds = 0
  }
  lastConfidence = judgment.confidence

  if (judgment.sufficient) {
    sufficient = true
  } else {
    // --- STEER: set focus for the next round ---
    steer = judgment.nextSteer || steer
  }
}

phase('Land')

const escalated = !sufficient
const reason = sufficient
  ? 'goal met sufficiently'
  : (round >= maxRounds ? 'round budget exhausted' : 'escalation cord fired (diminishing returns)')

log(`Goal-seek ended after ${round} round(s): ${reason}`)

// Emit the result based on what was requested
const emitResult = await agent(
  `You are landing a goal-seek. Produce the final ${emit} from what was learned.

  GOAL: ${goal}
  OUTCOME: ${sufficient ? 'goal met sufficiently' : 'stopped without full sufficiency (' + reason + ')'}

  FULL JOURNAL:
  ${journal.map((j, i) => `Round ${i + 1}: ${j.finding}\n  progress: ${j.progress}${j.blockers && j.blockers.length ? '\n  blockers: ' + j.blockers.join('; ') : ''}`).join('\n\n')}

  ${emit === 'answer' ? 'Produce a direct ANSWER to the goal, with confidence and caveats.' : ''}
  ${emit === 'plan' ? 'Produce a PLAN (ordered steps) — this may hand off to syndicate-campaign for execution.' : ''}
  ${emit === 'artifact' ? 'Summarize the ARTIFACT(S) produced and their state (working/partial).' : ''}
  ${escalated ? 'Since we escalated, clearly state what remains unresolved and what a human should decide.' : ''}

  Return a JSON object with:
  - result: string — the ${emit}
  - confidence: number 0-100
  - unresolved: array of strings — what's still open (empty if fully resolved)
  - handoff: string or null — if this should go to campaign/forge next, describe it`,
  {
    label: 'goalseek:land',
    phase: 'Land',
    schema: {
      type: 'object',
      properties: {
        result: { type: 'string' },
        confidence: { type: 'number' },
        unresolved: { type: 'array', items: { type: 'string' } },
        handoff: { type: ['string', 'null'] }
      },
      required: ['result', 'confidence']
    }
  }
)

return {
  status: sufficient ? 'sufficient' : 'escalated',
  goal,
  rounds: round,
  reason,
  emit,
  result: emitResult ? emitResult.result : '(landing failed)',
  confidence: emitResult ? emitResult.confidence : 0,
  unresolved: emitResult ? emitResult.unresolved || [] : [],
  handoff: emitResult ? emitResult.handoff : null,
  journal: journal.map(j => ({ round: j.round, finding: j.finding, progress: j.progress }))
}
