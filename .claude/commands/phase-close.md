---
description: Verify done criteria, tag phase, and scaffold the next phase
---

For the current phase (from `.control/progress/STATE.md`):

1. **Check working tree is clean.** Run `git status --porcelain`. If non-empty, stop and ask the user to commit or stash. Do not advance.
2. Re-read the current phase's `README.md` done criteria.
3. Verify each criterion. For automated ones, run the commands and report results. For manual ones, ask the user to confirm.
4. Verify `.control/issues/OPEN/` has no items tagged `phase:<N>-blocker`.
5. Verify test / eval status in STATE.md is green.
6. **If any criterion fails, stop.** List what's missing. Do not advance.
7. If all pass:
   - Create the phase tag: `git tag phase-<N>-<name>-closed` with a message summarising what shipped.
   - Update `.control/progress/STATE.md`: current phase → `<N+1>`, step → `<N+1>.1`, Last-phase-tag → the new tag, reset "Attempts that didn't work" and "In-flight work", update next action.
   - Scaffold `.control/phases/phase-<N+1>-<name>/`:
     - Copy `.control/templates/phase-readme.md` → new phase's `README.md`.
     - Copy `.control/templates/phase-steps.md` → new phase's `steps.md`.
     - Fill in the copied scaffolds with content from `.control/architecture/phase-plan.md`'s Phase `<N+1>` entry — typically Goal, Outcome, and the sub-step list under Done criteria. **Do NOT fill the `## Why this phase exists` section from phase-plan.md** — that section is reserved for the carry-forward logic (next sub-bullet) plus the operator's post-scaffold edits.
   - Write the kickoff prompt to `.control/progress/next.md`.
   - Commit: `chore(phase-<N>): close phase <N>, kick off phase <N+1>`.
   - Append a journal entry: "Phase <N> closed (tag: `phase-<N>-<name>-closed`, commit: `<sha>`); Phase <N+1> kicked off."
   - Print the next-session prompt for the user.
