---
name: continue
description: "Resume unfinished work on this repo from a prior session — reads pipeline state + the resume memory, reconciles with git, summarizes where you left off, and picks up the exact next step. The resume front-door (like /engage is the start front-door)."
---

# /continue — Resume Where You Left Off

Say **"continue"** (or run `/continue`) at the start of a session on a repo where a prior
session ended with work still in flight. This reconstructs the state and resumes — you do
NOT have to re-explain what you were doing.

## Steps

### 1. Load the resume state (first source with real content wins)
a. **Active pipeline** — `~/.syndicate/scripts/pipeline-state.sh show` (reads
   `~/.syndicate/pipelines/current.json`). If a pipeline is mid-flight, this is the
   authoritative what's-in-progress / what's-next / concerns.
b. **Resume-state memory** — the durable project memories already loaded this session
   (the `MEMORY.md` index + the `*-plan` / `*-resume` / `*-state` memory files). These
   record what's DONE, the exact NEXT step, and any locked decisions. (These get written
   when a session pauses — see "Recording work-left" below.)
c. **Recall** — if (a) and (b) are thin, run
   `~/.syndicate/scripts/recall.sh --repo <cwd> "<topic>"` for the last 2-3 sessions +
   merge history.

### 2. Reconcile with reality (never trust stale state)
- `git fetch origin`, then verify branch / PR / merge status for anything the resume
  state references. A note saying "PR open" may have been merged since — the forge is the
  source of truth, not the stale note (doctrine: fetch before you reconstruct git state).
- Confirm the files / issues / branches the plan names still exist.
- If reconciliation contradicts the resume note, TRUST reality and say what changed.

### 3. Summarize (3-5 lines)
State plainly: what's **DONE**, what's **NEXT** (the exact next action), any **BLOCKERS** —
and cite the source (pipeline / memory / recall). Keep it tight; this is a status handoff,
not a lecture.

### 4. Resume
Take the next action through the normal Syndicate dispatch doctrine (classify → one-line
plan → act). Do NOT restart from scratch — pick up at the next step. Honor any locked
decisions recorded in the resume state; do not re-litigate them.
If nothing unfinished is found, say so and ask what to work on (clean slate).

## Recording work-left (the other half — required for this to work next time)

A paused session must leave state behind, or there's nothing to continue from:
- **Mid-pipeline:** `pipeline-state.sh` already persists `current.json` — nothing extra.
- **Otherwise:** write/update a **resume-state memory** (`type: project`) capturing what's
  done, the EXACT next step, and any locked decisions; index it in `MEMORY.md`. Do this
  when the user pauses ("do that tomorrow", "let's stop here") or a session ends with open
  work. Convert relative dates to absolute so the note ages correctly.

## Notes
- Layers on the doctrine: `/continue` is the **resume** front-door, as `/engage` is the
  **start** front-door and `/syndicate` arms self-dispatch. After continuing, normal
  routing applies.
- If several work-threads are active (multiple `*-resume` memories), summarize each and
  ask which to pick up — don't guess.
- This is read-mostly: step 2 does a `git fetch` and step 1 reads state. It does not commit
  or edit; resuming the work does that through the normal gated flow.
