---
description: Print the canonical next Control command for current state — read-only recommendation
---

Inspect current Control state and emit the canonical next Control command. Read-only — recommends, does not execute.

## State inputs to read

In this order, capturing each into a variable for the decision tree:

1. **`.control/progress/STATE.md`** — full file. Extract: current phase, current step, cursor phase dir path, "Open blockers" list, "Test/eval status" line, "In-flight work" notes, "Last phase tag" field.
2. **`git status --porcelain`** — record dirty/clean and the dirty path list.
3. **`.control/phases/<cursor-phase>/steps.md`** — the unchecked items (`- [ ]` lines) and any `[HALT]` markers on upcoming steps (see "Conventions" below for the marker format).
4. **`git describe --tags --abbrev=0`** — last tag (or "none"). For Priority 4 / 5 comparisons: substitute `{n}` and `{name}` from STATE.md's current cursor phase into `${CONTROL_PHASE_CLOSE_TAG_FORMAT}` to compute the expected close-tag pattern (e.g., cursor `phase-3-payment-gateway` + format `phase-{n}-{name}-closed` → expected `phase-3-payment-gateway-closed`). Strip backticks and take the first whitespace-token of `git describe`'s output before comparison (matches `.claude/hooks/session-start-load.sh:55` parsing).
5. **`.control/issues/OPEN/`** listing — for each blocker file, capture: file id, and whether the `## Hypothesis` section content is filled-in (not whitespace-only AND not the literal `.control/templates/issue.md` L18 placeholder `<Best guess at cause. Update as investigation proceeds.>`). Do NOT try to detect regression-test presence from the issue file — the template's `## Resolution` section at L20-25 always contains a "Regression test:" bullet label as a stub, which would false-positive any text search; `/close-issue` Step 2 has the authoritative test-detection gate.
6. **`.control/architecture/phase-plan.md`** — total phase count, for the all-phases-complete check.
7. **`.control/config.sh`** — source defensively: `. ./.control/config.sh 2>/dev/null || true`. Use `${CONTROL_PHASE_CLOSE_TAG_FORMAT:-phase-{n}-{name}-closed}`, `${CONTROL_COMMIT_FORMAT:-{type}({phase}.{step}): {subject}}`, and `${CONTROL_HALT_CONDITIONS:-...}` for formatting. Defensive default pattern matches `.claude/hooks/stop-snapshot.sh:13` precedent so existing installs whose `kind=project` config hasn't been manual-merged still work.

## Decision tree

First-match wins. Walk in priority order; emit the recommendation and stop on the first match. The priority order mirrors `/work-next` (`.claude/commands/work-next.md` L7-28) so the two commands always agree on the canonical next action.

### Priority 0 — prerequisites (project not ready for normal work)

| State | Recommendation |
|-------|---------------|
| STATE.md missing | `Run /bootstrap — STATE.md missing; project not yet initialised.` |
| STATE.md template-shape (regex per `.control/PROJECT_PROTOCOL.md` § "Drift detection contract" L855-874: `<short-sha>` \| `<YYYY-MM-DD>` \| `<sha>`) | `Run /bootstrap — STATE.md still has template placeholders.` |
| STATE.md Git state section unparseable (none of the four parser-contract field labels present) | `Run /validate — STATE.md Git state section is unparseable (schema broken).` |
| STATE.md cursor phase dir doesn't exist | `Run /validate — STATE.md drift: cursor phase directory missing.` |

### Priority 1 — open blockers (mirrors /work-next priority 1)

| State | Recommendation |
|-------|---------------|
| Blocker `## Hypothesis` section is empty (whitespace-only) OR contains the literal template stub `<Best guess at cause. Update as investigation proceeds.>` | `[HALT] Blocker <id> has no hypothesis. Investigate or run /new-adr.` |
| Blocker `## Hypothesis` section has any non-template content | `For <id>: investigate, fix, write a regression test, then run /close-issue <id>.` |

**Multi-blocker rule.** If multiple files exist in `.control/issues/OPEN/`, walk all of them and pick the WORST state per priority — HALT (no-hypothesis) trumps work-it (with-hypothesis). On ties (multiple no-hypothesis blockers, or multiple with-hypothesis), name the lowest-id blocker first; the operator handles them in order.

### Priority 2 — failing tests / eval (mirrors /work-next priority 2)

| State | Recommendation |
|-------|---------------|
| STATE.md "Test/eval status" not green AND "Notes for next session" describes obvious fix | `Fix the failing test/eval and commit.` |
| STATE.md "Test/eval status" not green AND fix unclear | `[HALT] Failing test/eval — multiple plausible fixes (ambiguous_failing_test).` |

### Priority 3 — current phase work (mirrors /work-next priority 3)

| State | Recommendation |
|-------|---------------|
| Tree dirty + STATE.md current step has `- [ ]` in steps.md | `Commit step (<type>(<phase>.<step>): <subject> per CONTROL_COMMIT_FORMAT) and flip - [ ] → - [x] on the matching steps.md line.` |
| Only ignorable paths dirty (see "Ignorable-dirty rule" below) | (treat as effectively clean — fall through to clean rows) |
| Tree clean + next unchecked step + no `[HALT]` marker | `Continue with step <phase>.<N>: <step description from steps.md>.` |
| Tree clean + next unchecked step has `[HALT]` marker | `[HALT] <halt-reason from steps.md>. Do not proceed autonomously.` |

### Priority 4 — phase-close (mirrors /work-next priority 4)

| State | Recommendation |
|-------|---------------|
| Tree clean + every checkbox `- [x]` + last tag does NOT match `${CONTROL_PHASE_CLOSE_TAG_FORMAT}` for current cursor phase | `Run /phase-close.` |

### Priority 5 — between phases (mirrors /work-next priority 5)

| State | Recommendation |
|-------|---------------|
| Last tag matches current cursor phase's close-tag pattern + `.control/phases/phase-<N+1>-*/` exists | `Pick step 1 of the new phase (use /work-next or pick manually).` |
| Last tag matches + no next-phase directory | `Run /session-end to close the day, OR author the next phase's .control/phases/phase-<N+1>-<name>/{README.md,steps.md} now.` |

### Priority 6 — all phases complete (mirrors /work-next priority 6)

| State | Recommendation |
|-------|---------------|
| Tree clean + no further phase in `phase-plan.md` beyond current cursor | `All phases complete per phase-plan.md. Run /session-end, or open a new phase plan.` |

### Fallback

| State | Recommendation |
|-------|---------------|
| No row matched (shouldn't happen given coverage) | `Run /validate — couldn't determine next action; protocol consistency may be broken.` |

## Ignorable-dirty rule

In CONSUMER projects, `.control/snapshots/` is gitignored via `setup.sh` L154 — files there don't appear in `git status --porcelain` to begin with. In the SOURCE repo (Control's own dev repo), the same gitignore line is present (added by I1.4, commit `03dc982`). The list below is a SAFETY NET for the narrow window before `.gitignore` takes effect (e.g., fresh install before `git add .gitignore`); not the primary mechanism.

A dirty path is "ignorable" if it matches:
- `.claude/scheduled_tasks.lock` — harness-internal lock; harmless churn
- `.control/snapshots/*` — already gitignored (belt-and-suspenders only)

A dirty path is **NOT** ignorable (must be a conscious edit) if it matches:
- `.githooks/*` — per `.control/PROJECT_PROTOCOL.md` § "Commit-msg contract" L1092; tracked, managed by Control
- `.control/issues/OPEN/*`
- `.control/architecture/decisions/*` (ADRs are immutable per CLAUDE.md invariant)
- Any other path in the working tree

## Conventions

**`[HALT]` marker in steps.md.** This command reads steps.md and looks for the literal token `[HALT]` as the first non-checkbox token on a step line. Format: `- [ ] N.M [HALT] <reason text>`. The reason text after `[HALT]` is emitted verbatim. **This convention is introduced by `/control-next`** — peer commands (`/work-next`, `/phase-close`) currently route HALTs through `CONTROL_HALT_CONDITIONS` (config.sh runtime conditions) rather than steps.md inline markers. Operators flag pause-for-human steps by inserting `[HALT]` after the step number; if not used, the priority-3 row "tree clean + unchecked step + no `[HALT]`" matches and the recommendation is "Continue with step N.M". Documenting this convention in `.control/PROJECT_PROTOCOL.md` § "Sub-step discipline" before F10/F11/F12 reference it is a follow-up doc-sync chore.

## Output format

Plain prose. Single-line recommendation followed by an optional one-line justification. No ANSI color, no JSON in v1 of this skill (`--json` deferred to v1.5.x).

## Limitations

- Does NOT execute the recommended action. It reports.
- Does NOT detect `/loop` activity from observable state. If `/loop /work-next` is in flight, the recommendation reflects state at this turn and may be stale by the next turn.
- Does NOT validate STATE.md schema beyond the parser-contract check (Priority 0 row 3). Use `/validate` for full consistency checks.
- Does NOT enforce commit shape — that's `.githooks/commit-msg` per `.control/PROJECT_PROTOCOL.md` § "Commit-msg contract".
- Does NOT detect new ADR files dirty alone (without a step context). If the only dirty path is `.control/architecture/decisions/NNNN-*.md`, this command falls through to Priority 3 row 1 (recommends commit per the current step's commit shape). Operators committing standalone ADRs use `docs(adr): ADR-NNNN <subject>` per the Commit-msg contract's `adr` parens-allowlist entry.

## Related

- `/work-next` — autonomous pick AND execute (this command's logic + execution layer)
- `/validate` — sanity-check protocol files for consistency
- `.control/PROJECT_PROTOCOL.md` § "Drift detection contract" — canonical template-form sentinels + parser contract
- `.control/PROJECT_PROTOCOL.md` § "Commit-msg contract" — commit shape regex + bypass cases
- CLAUDE.md L22 invariant — assistant-side mirror of this command (state next command at every transition)
