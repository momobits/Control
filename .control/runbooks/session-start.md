# Session start protocol

1. **Read state** — `.control/progress/STATE.md`. Note every field: phase, step, next action, git state, blockers, in-flight work, test/eval status, recent decisions, attempts that didn't work, notes.
2. **Read phase context** — the README and steps files for the phase path in STATE.md.
3. **Scan open issues** — list every file in `.control/issues/OPEN/`. Identify items tagged as blockers for the current phase.
4. **Respond to drift signals.** The SessionStart hook (`.claude/hooks/session-start-load.{sh,ps1}`) emits zero or more `[control:drift]` blocks. Each block has a `type:` field (e.g. `state-md-missing`, `state-md-template`, `state-md-unparseable`, `branch-mismatch`, `commit-mismatch`, `uncommitted-mismatch`, `tag-mismatch`); mismatch types also have `expected:` / `actual:` fields. **If any `[control:drift]` block is present**, narrate the drift to the operator in plain English (e.g. "STATE.md says branch=X but actual is Y — sync before proceeding?") and pause for reconciliation. Do NOT silently proceed. **If the `[control:SessionStart]` block is NOT present** (hook absent or runbook invoked manually outside the hook flow), do a manual compare: `git status --porcelain`, `git log -1 --oneline`, `git rev-parse --abbrev-ref HEAD`, `git describe --tags --abbrev=0` against STATE.md's Git state section. Any mismatch is drift — flag it, don't silently proceed.
5. **Report to operator.** Default is narrative; verbose is structured. The operator sees the narrative unless they ask for the verbose block ("show me the status block", "show full state", or pass `--verbose` to a slash command).

   **Narrative (default).** 2–4 plain-English sentences. Derive from the `[control:state]` hook block + STATE.md. Lead with the phase/step continuation, then current health (working tree, blockers, last test), then the proposed next action. Do NOT paste the raw `[control:state]` block at the operator.

   Example:
   > **Continuing Phase 2 (DSPy QueryPlanner), step 2.3.**
   > Last session implemented 2.2 base classes (`abc123`). Working tree clean, no blockers, last test green.
   >
   > **Next:** define the QueryPlanner signature per spec §3.2.
   >
   > Ready?

   **Verbose (on request, OR forced by drift).** Canonical structured shape, used by all status-emitting commands (`/session-start`, `/work-next`, `/phase-close`):

   ```
   Phase <N> — <name>, step <N.M>
   Last action: <from STATE.md "Recently completed[0]">
   Git: branch=<...>, last=<sha> <subject>, uncommitted=<yes|no>, tag=<last phase tag>
   Git sync: matches STATE.md  OR  drift: <type-and-detail per [control:drift] blocks>
   Open blockers: <count, with IDs> OR None
   Test/eval status: <from STATE.md>
   Proposed next action: <from STATE.md>
   ```

   **Drift forces verbose.** If step 4 surfaced any `[control:drift]` block, narrate the drift first AND show the verbose block. Don't proceed until the operator confirms reconciliation.

5b. **Design decisions awaiting operator input.** If `.control/progress/next.md` surfaces a `## Decisions awaiting your input` section, or STATE.md's "Notes for next session" / "Next action" flags an open design choice for the upcoming step, expand it inline before asking for go. For each option present: **(i) what concretely changes** (schema additions, code shape, file additions), **(ii) what the operator sees** (sample CLI output, sample data shape, sample error), **(iii) cost / scope impact** (how it affects the current step's budget and surrounding work), **(iv) trade-off being accepted** (what each option costs, not just what it gains). End with a recommendation that names the trade-off, not just the lean. Do not shorthand design choices as labeled footnotes (`(a)` / `(b)` with one-line summaries) — that forces the operator to ask for the detail in a second turn, wasting context.

5c. **Recommend next action.** If Step 5b expanded a design decision, SKIP this step (the decision takes precedence over a generic recommendation). Otherwise, after the status report, apply the priority decision tree from `.claude/commands/control-next.md` (read the file, walk the priority order against current state, emit the recommendation) and append: `Recommended next: <recommendation>` followed by `(Run /control-next --why for the state inputs behind this.)`. Recommendation only — wait for the operator's go before executing. Feature-flag: if `.claude/commands/control-next.md` does not exist, skip this step silently. *(v2.1 note: `/control-next` will be removed and its priority logic absorbed into this step via `.control/runbooks/work-priority.md`.)*

6. **Wait for confirmation.** Do not edit code before the operator says go.

If `SessionStart` hook is installed, steps 1-5 run automatically and prefix the session with the structured `[control:*]` data blocks for Claude to read. Claude turns the data into the narrative the operator sees.
