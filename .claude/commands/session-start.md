---
description: Run the Control session bootstrap protocol
---

Follow `.control/runbooks/session-start.md` exactly:

1. Read `.control/progress/STATE.md`.
2. Read the current phase's `README.md` and `steps.md` (path in STATE.md).
3. List files in `.control/issues/OPEN/` and identify blockers for the current phase.
4. **Respond to drift signals.** The SessionStart hook (`.claude/hooks/session-start-load.sh`) parses STATE.md and emits `[DRIFT] ...` lines BEFORE the `[control:SessionStart] Bootstrap` block when STATE.md disagrees with reality, the file is missing, or the Git state section is unparseable. **If you can see the `[control:SessionStart] Bootstrap` block in the SessionStart prompt above** (the hook ran), trust the hook's output: surface any `[DRIFT]` lines under `Git sync:` and pause for operator reconciliation before proceeding; absence of `[DRIFT]` lines means no drift was detected — proceed to the status block. **If the bootstrap block is NOT present** (hook absent — e.g., `/session-start` invoked manually outside the SessionStart hook flow, or hooks not configured), do a manual compare: `git status --porcelain`, `git log -1 --oneline`, `git rev-parse --abbrev-ref HEAD`, `git describe --tags --abbrev=0` against STATE.md's "Git state" section. Any mismatch is a drift signal — flag it, don't silently proceed.
5. Report a status block in this exact shape:
   ```
   Phase <N> — <name>, step <N.M>
   Last action: <from STATE.md's Recently completed[0]>
   Git: branch=<...>, last=<sha> <subject>, uncommitted=<yes/no>, tag=<last phase tag>
   Git sync: ✓ matches STATE.md  OR  ⚠ drift: <details>
   Open blockers: <count, with IDs> OR None
   Test/eval status: <from STATE.md>
   Proposed next action: <from STATE.md>
   Ready to proceed?
   ```
5b. **Design decisions awaiting operator input.** If `.control/progress/next.md` surfaces a `## Decisions awaiting your input` section, or STATE.md's "Notes for next session" / "Next action" flags an open design choice for the upcoming step, expand it inline before asking for go. For each option present:
   - **(i) What concretely changes** — schema additions, code shape, file additions.
   - **(ii) What the operator sees** — sample CLI output, sample data shape, sample error.
   - **(iii) Cost / scope impact** — how it affects the current step's budget and surrounding work.
   - **(iv) Trade-off being accepted** — what each option costs, not just what it gains.
   End with a recommendation that names the trade-off being accepted, not just the lean. Do not present design choices as labeled footnotes (`(a)` / `(b)` with one-line summaries) — that forces the operator to ask for the detail in a second turn, wasting context.
5c. **Recommend next action.** If Step 5b expanded a design decision, SKIP this step (the decision takes precedence over a generic recommendation). Otherwise, after the status block, apply the priority decision tree from `.claude/commands/control-next.md` (read the file, walk the priority order against current state, emit the recommendation) and append: `Recommended next: <recommendation>` followed by `(Run /control-next --why for the state inputs behind this.)`. Recommendation only — wait for the user's go before executing. Feature-flag: if `.claude/commands/control-next.md` does not exist, skip this step silently.
6. Wait for the user's go before editing any code.
