# Improvements — Control v1.4.0 proposal

> Proposal for upgrading Control based on experience installing it into factory5 (Phase 6, 2026-04-21). Five additive improvements, one strength to preserve, one principle. Non-breaking; shipped as a minor version bump (1.3.0 → 1.4.0) via the existing `UPGRADE=1` flow.

---

## Context — where this came from

Control was installed into factory5 in 2026-04-21, after the project had already closed 5 phases with its own hand-rolled conventions. factory5 has:

- **17 ADRs averaging ~150 lines each** (ADR-0017 is 223 lines)
- **7 issue files, incident-grade** — I007 is 206 lines (Symptom with log snippets / Repro tied to a specific directive ID / Hypothesis with ruled-out alternatives / Resolution triple of fix-commit + regression-test path + diff-summary)
- **Per-phase narrative progress docs** — `docs/Phase5_Progress.md`, `docs/Phase6_Progress.md`, 100–300 lines each
- **A 2554-line append-only `docs/PROGRESS.md`** — chronological session log
- **Explicit forward-pointers between phases** — "Out of scope for Phase 6 — deferred to Phase 7" lists carry the institutional memory between phases

Control's templates were installed alongside. The mismatch revealed 5 gaps — not bugs, just places where Control's template seeds give authors no model of depth. The improvements below close those gaps without breaking Control's minimalist philosophy.

**Design principle (unchanged):** Control ships structure, not content. Projects fill in richness. The improvements here ship *better starting points* (examples + section prompts), not boilerplate content.

---

## Improvement 1 — Ship a filled ADR example

### Current state

`.control/templates/adr.md` is a 20-line skeleton:

```markdown
# ADR-<NNNN>: <Decision title>
**Date:** <YYYY-MM-DD>
**Status:** proposed | accepted | superseded by ADR-<M>
**Phase when decided:** <N>

## Context
<The forces at play, the problem, the constraints.>

## Decision
<The choice made.>

## Alternatives considered
- <Option A> — rejected because <reason>
- <Option B> — rejected because <reason>

## Consequences
- Positive: <...>
- Negative: <...>
- Follow-up work: <...>
```

### Gap

No model of depth. Authors new to ADRs will produce 30-line shells. factory5's ADR-0017 is 223 lines because its author had a mental model of what "Context" means (forces + constraints + recent signal), what "Decision" should argue (which option picked, rationale per-clause, explicit scope boundaries), and what "Alternatives" must contain (reject-reasons with one-sentence-each, not just names).

### Proposed change

Add a second file alongside the skeleton:

`.control/templates/adr-example.md` — a filled example ADR on a realistic engineering decision, demonstrating:

- **Context** with enumerated forces (1–6 lines each) + current-state signal + recent-incident pointer
- **Decision** with rationale per-clause + explicit scope (what's in, what's out)
- **Alternatives** with reject-reasons, not just "not chosen" — include tiered alternatives (tier 1 / 2 / 3) where the decision could be phased
- **Consequences** split into Positive / Negative / Follow-up work
- **Implementation notes** (optional section) — gotchas discovered during the fix that the original ADR author didn't anticipate

### Source material

factory5's ADR-0017 (`docs/decisions/0017-assessor-project-env-provisioning.md`) is a license-compatible exemplar — 223 lines, real engineering decision (assessor Python env provisioning), tier-ed alternatives (tier 1 / 2 / 3), Implementation Notes addition post-shipping. Sanitize project-specific references (factory, assessor, pytest) to a generic example — suggested substitute: "CI test runner needs isolated per-project environment" is domain-agnostic enough.

### Files to change

- **ADD** `.control/templates/adr-example.md` (sanitized from factory5 ADR-0017)
- **UPDATE** `.control/templates/adr.md` top line: add `> See adr-example.md for a filled example at production depth.`
- **UPDATE** `.claude/commands/new-adr.md` to reference both template files in its body

### Version impact

Additive. Safe under `UPGRADE=1` (templates are `kind=framework`, refreshed on upgrade per `setup.sh` line 109–115).

---

## Improvement 2 — Ship a filled issue example

### Current state

`.control/templates/issue.md` is a 23-line skeleton, headers only:

```markdown
# ISSUE-<YYYY-MM-DD>-<slug>
**Severity:** blocker | major
**Discovered:** <YYYY-MM-DD>
**Phase/step:** <N.M>
**Status:** open | in-progress | fix-pending-test | resolved

## Symptom
## Repro
## Hypothesis
## Resolution
- **Fix commit:** `<sha>` — <one-line>
- **Regression test:** `<path>` — covers <specific failure mode>
- **Diff summary:** <what changed and why>
```

### Gap

Same pattern as ADR — authors will produce 10-line issues that are hard to debug later. factory5's I007 is 206 lines because it documents:

- Exact observable symptom with log snippets (not just prose)
- Repro steps tied to a specific run (directive ID, workspace path, timestamp)
- Hypothesis with alternatives considered and ruled out one-by-one
- Resolution with commit SHA + test path + surrounding-context diff — the triple is what lets a reviewer 6 months later understand *why* the fix is correct

### Proposed change

Add `.control/templates/issue-example.md` — filled issue at production depth, showing:

- Symptom with concrete log snippet / error output (not prose paraphrase)
- Repro steps citing a specific run (directive ID, workspace path, timestamp)
- Hypothesis with alternatives considered and ruled out
- Resolution triple (fix commit SHA, regression test path, diff summary)
- Post-close notes if behavior drifted after fix

### Source material

factory5's I007 (`docs/issues/I007-builder-pip-install-pollutes-user-site.md`, 206 lines) or I005 / I006 — similar shape, similar depth. Sanitize to a generic domain (suggested: "webhook handler silently drops events when upstream returns 5xx" — protocol-agnostic, touches common patterns like retries, dedup, logging).

### Files to change

- **ADD** `.control/templates/issue-example.md` (sanitized from factory5 I007)
- **UPDATE** `.control/templates/issue.md`: top-line reference to the example
- **UPDATE** `.claude/commands/new-issue.md` to reference both template files

### Version impact

Additive. Same as Improvement 1.

---

## Improvement 3 — Phase README narrative section

### Current state

`.control/templates/phase-readme.md` (31 lines) has: Goal (1 sentence), Outcome (1 sentence), Sub-steps reference, Done criteria checklist, Rollback plan, ADRs list.

### Gap

factory5's `Phase5_Progress.md` and `Phase6_Progress.md` have rich narrative sections: "Where we were, end of [previous phase]", "Where we are, end of [current sub-phase]", "What needs to happen next". These sections carry the institutional memory between phases — they're what lets a new session drop in 3 months later and understand *why* this phase exists.

Control's phase README template has no prompt for this. Goal + Outcome is too terse. A `/session-start` reader sees "Goal: fix the verifier hallucination" without understanding what the verifier is, why it hallucinates, or what the forcing function was.

### Proposed change

Add two new sections to `.control/templates/phase-readme.md` between "Outcome" and "Sub-steps":

```markdown
## Where we were, end of Phase <N-1>

<One paragraph + bullets. What the previous phase shipped that this phase builds on.
What's already proven. What infrastructure this phase can rely on without re-paving.>

## Why this phase exists

<One paragraph. The forcing function, gap, or operator-pain that motivates this phase.
Link to issues, findings, incident reports, or external commitments that drove the decision
to do this work now (rather than later or never).>
```

Authors may leave these terse for small phases, but the prompts shape the right thinking. A phase that can't justify "why now" probably shouldn't be charter-ed.

### Source material

factory5's `docs/Phase6_Progress.md` — see sections "Where we were, end of Phase 5" and "Phase 6 scope proposal → forcing function".

### Files to change

- **UPDATE** `.control/templates/phase-readme.md` with two new sections and a short header comment explaining them

### Version impact

Additive. Existing phase READMEs (already populated) won't regenerate; only new phases scaffolded via `/phase-close` get the updated shape. Authors can retrofit old phase READMEs if they want, but it's not forced.

---

## Improvement 4 — Forward-pointers between phases

### Current state

`.control/architecture/phase-plan.md` template is a table + per-phase summary. Each phase stands alone.

`.control/templates/phase-readme.md` ends phases cleanly (Done criteria, Rollback, ADRs) but has no outbound pointer to what's *deferred to the next phase*.

### Gap

factory5 relies heavily on "Out of scope for Phase N — deferred to Phase N+1" lists. These carry items that surface mid-phase but exceed scope. Without an explicit place to park them, they either get forgotten (dropped signal) or bloat the current phase (scope creep). Six months later you can't reconstruct *why* a particular feature appeared in Phase 7 rather than Phase 6 — unless the Phase 6 README had told you "here's what we deferred to 7 and why."

### Proposed change

Add a new section to `.control/templates/phase-readme.md` after "ADRs decided in this phase":

```markdown
## Deferred to Phase <N+1> (or later)

Items that surfaced during this phase's work but exceed scope. Each entry has a one-line
reason for deferral. Copy forward into the next phase's `Why this phase exists` section
when it activates.

- <item> — <one-line reason for deferral>
- <item> — <...>
```

And reflect this in `/phase-close` protocol: when a phase closes, copy its "Deferred" list into the next phase's scaffolded README as a starting-point for "Why this phase exists" + potential sub-steps.

### Source material

factory5's `docs/Phase6_Progress.md` "Out of scope for Phase 6" section — 6 bullets, each with a reason ("Telegram channel — saved until after 6b validates the channel-shape"; "Web UI — bigger build than the above; its own phase").

### Files to change

- **UPDATE** `.control/templates/phase-readme.md` with the new "Deferred" section
- **UPDATE** `.claude/commands/phase-close.md` step 7: `"When scaffolding next phase, read current phase's 'Deferred to Phase N+1' section and seed the new phase's 'Why this phase exists' with a summary of the carry-forwards."`

### Version impact

Additive. Existing phase READMEs don't regenerate; new phases scaffolded post-upgrade get the shape.

---

## Improvement 5 — Acknowledge long-form progress

### Current state

`.control/progress/journal.md` template says "Append-only, newest on top. One entry per session, short."

Control's design: STATE.md is the cursor, journal.md is a terse log. History lives in commit messages + tags.

### Gap

factory5 maintains `docs/PROGRESS.md` (2554 lines) as a narrative history of every session. This is where decision *rationale* lives — the "why did we pick approach A over B in Phase 3?" question. Commit messages are too terse to carry that; tags carry nothing; STATE.md is overwritten every session.

Control doesn't preclude this — `docs/` is explicitly untouched — but it also doesn't *acknowledge* it. A new Control-instantiated project has no prompt to keep a long-form progress log, so many probably don't — and then 9 months later nobody remembers why a particular tradeoff was made.

### Proposed change

Two small additions:

1. **UPDATE** `.control/runbooks/session-end.md` to include as step N:

   ```
   N. If the project keeps a long-form progress log (commonly `docs/PROGRESS.md`),
      append a session entry there before writing the one-line journal entry here.

      Control's `journal.md` is a cursor — one-liner per session, good for scanning
      "what happened when" at a glance. It's not a replacement for narrative history.

      For multi-month projects, the long-form log pays for itself within two phases.
      See `.control/PROJECT_PROTOCOL.md` "Documentation layers" for the split.
   ```

2. **UPDATE** `.control/PROJECT_PROTOCOL.md` — add or extend a "Documentation layers" section:

   ```markdown
   ## Documentation layers

   Two complementary layers; Control manages one, the project owns the other.

   ### Operational (Control-managed, under `.control/`)

   - `progress/STATE.md` — current cursor; replaced every session
   - `progress/journal.md` — one-liner per session; terse log
   - `progress/next.md` — auto-written handoff prompt
   - `phases/phase-N-<name>/` — active step checklists
   - `architecture/decisions/` — ADRs (if the project uses Control's ADR home)
   - `issues/{OPEN,RESOLVED}/` — issue files (if the project uses Control's issue home)

   ### Long-form (project-owned, under `docs/` or equivalent)

   - Narrative progress log (`docs/PROGRESS.md` or similar) — session-at-end append.
     Cursor = state; narrative = story. Keep both.
   - Architecture / contracts / skills / agents docs — the *what* of the system
   - Phase-level retrospectives — per-phase narrative ("where we were / where we are / what's next")
   - ADRs and issues if the project prefers to own these under `docs/` rather than under `.control/`

   **When to use which:**
   - For projects expected to live past ~20 ADRs or ~10 phases, keep ADRs and issues
     under `docs/` with project-specific shape (see factory5's `docs/decisions/` and
     `docs/issues/` for a real example). Use `.control/` for the operational cursor only.
   - For smaller or shorter-lived projects, keeping ADRs and issues under `.control/`
     is fine — one less doc tree to maintain.
   - Long-form progress (`docs/PROGRESS.md`) is worth keeping for any project expected
     to last more than ~5 sessions, regardless of size.
   ```

### Source material

- factory5's `docs/PROGRESS.md` (2554 lines) as the canonical long-form example
- factory5's `CLAUDE.md` section "Control framework (operational layer)" added 2026-04-21 — a real-world example of a project using Control for operational cursor while keeping its own doc shape for long-form content

### Files to change

- **UPDATE** `.control/runbooks/session-end.md` — add long-form-log reminder step
- **UPDATE** `.control/PROJECT_PROTOCOL.md` — add "Documentation layers" section
- **OPTIONAL:** UPDATE the `CLAUDE.md` template (at repo root, the one the installer ships) with a "Documentation layers" section pointing at the split; factory5's augmented `CLAUDE.md` is a reference

### Version impact

Additive. Existing projects don't need to adopt; the prompts just exist for projects that want them.

---

## Strength to preserve — severity gating on issues

Control's `CONTROL_ISSUE_FILE_REQUIRED_FOR="blocker major"` / `CONTROL_ISSUE_JOURNAL_ONLY="minor"` is a genuine improvement over factory5's "file every issue" practice. factory5 has 7 issue files including I007 (LOW severity) — arguably a journal line would have served. factory5's discipline works because the authors are diligent, but Control's severity gate enforces it mechanically.

`/close-issue` refusing to close a major/blocker without a regression test is the discipline factory5 imposes by convention (all 7 factory5 issues have regression tests) but Control enforces mechanically.

**Do not weaken either of these in v1.4.0.**

---

## Principle to preserve — minimalism

Control's templates are skeletons by design. These five improvements add *examples* (filled companions) and *section prompts* (forward-pointers, narrative sections) — not boilerplate content. The goal is to give authors better mental models without making the template itself heavier.

Three lines that should never change:

- Templates are starting skeletons, not content.
- `docs/` is the project's namespace; Control touches only `.control/` and `.claude/`.
- STATE.md is a cursor; narrative history lives in commit messages and project-owned docs.

---

## Version bump + rollout

**Proposed version:** 1.3.0 → 1.4.0 (minor — all additive, no breaking changes)

**Rollout checklist:**

1. Author the changes in the Control source (`G:\Projects\Small-Projects\Control\`)
2. Bump `VERSION` to `1.4.0`
3. Update `README.md` Upgrade walkthrough (no behavior change — `UPGRADE=1 bash setup.sh` picks up new templates automatically via the `*.md` glob loop in setup.sh lines 109–115)
4. Test upgrade against factory5: `cp -r /g/Projects/Small-Projects/Control /g/Projects/Large-Projects/factory/factory5/Control` → `UPGRADE=1 bash Control/setup.sh`
5. Verify: factory5's existing populated files (STATE.md, phase-plan.md, overview.md, CLAUDE.md) are preserved (they're `kind=project`); new template files appear in `.control/templates/`; existing templates refreshed.
6. Commit the Control source changes with a meaningful message
7. Tag `v1.4.0` in the Control repo

**Priority order** (if shipping incrementally rather than all-at-once):

1. **Improvement 1 (filled ADR example)** — biggest shape improvement for new projects. Affects every future ADR.
2. **Improvement 2 (filled issue example)** — paired with #1, same logic.
3. **Improvement 4 (forward-pointers)** — enables better phase-to-phase continuity. Small template change, big institutional-memory impact.
4. **Improvement 3 (phase README narrative)** — incremental value, but `/phase-close` scaffolding is the right place to introduce this.
5. **Improvement 5 (long-form progress acknowledgment)** — documentation-only; low-effort, low-impact, but a good capstone.

Shipping 1+2 alone would be a valuable v1.3.1 patch. Full 1–5 is v1.4.0.

---

## Out of scope for v1.4.0

- **No breaking changes.** No file deletions, no rename-type refactors of command files or hook names.
- **No new commands.** `/phase-close`, `/new-adr`, `/new-issue`, `/session-start`, `/session-end`, `/loop`, `/validate`, `/close-issue`, `/bootstrap`, `/new-spec-artifact` all stay as-is.
- **No hook changes.** PreCompact / SessionStart / SessionEnd / Stop / prune-snapshots untouched.
- **No config.sh additions.** All tunables stay as-is.
- **No change to the install flow.** `bash setup.sh` / `setup.ps1` / `uninstall.sh` behavior unchanged.
- **No change to STATE.md shape.** The cursor semantic is unchanged; existing installations' STATE.md files continue to work without migration.

---

## Acknowledgment — what Control gets right

Listing this so v1.4.0 doesn't try to "improve" what's already strong:

- **STATE.md as single-cursor, replaced every session.** Prevents bit-rot that append-only cursors accumulate. Correct call.
- **Commit-per-step + phase-close tags.** This is the operational discipline factory5 lacked before Control was installed.
- **PreCompact + SessionEnd hooks for auto-snapshot.** Saves hours of lost context recovery after a compaction event.
- **`/phase-close` as a mechanical done-criteria gate.** Verification before tag creation prevents phase-close-drift.
- **Severity gating on issues.** Already called out above.
- **`/close-issue` regression-test requirement.** Automatic enforcement of the "every bug needs a regression test" discipline.
- **PROJECT_PROTOCOL.md as a 1123-line framework reference.** Comprehensive without being overwhelming; well-sectioned.
- **The `kind=framework` vs `kind=project` distinction in `setup.sh`.** Safe upgrade path. Enables drop-in iteration without overwriting user content.
- **`docs/` left explicitly untouched.** Projects keep their own namespace for long-form content; no forced migration.
- **`/loop /work-next` with halt conditions.** Autonomy with guardrails, not autonomy-or-nothing.

---

## Open questions

Things to resolve before implementation starts:

1. **License on the example templates.** If ADR-example and issue-example are derivations of factory5's ADR-0017 and I007, what's the attribution / license? Probably simplest: rewrite from scratch with a generic domain rather than sanitize-and-derive.
2. **Where do filled examples live?** Option A: `.control/templates/adr-example.md` alongside the skeleton. Option B: `.control/examples/adr.md`. Option A is simpler (one directory); Option B is more discoverable.
3. **Should the `/phase-close` "copy deferred → next phase's Why" step happen automatically or prompt the user?** Probably automatic with "here's what I carried forward; edit before continuing" — balances automation with human-in-loop.
4. **Should PROJECT_PROTOCOL.md's "Documentation layers" section recommend for or against ADRs under `.control/` vs `docs/`?** Opinion: for small/short projects use `.control/`; for large/long-lived projects use `docs/`. Document both patterns; don't prescribe one.

---

**Author:** Claude Opus 4.7
**Date:** 2026-04-21
**Context:** Drafted during factory5 Phase 6 instantiation; sources real-world observations of Control template shell vs factory5 filled content.
**Status:** Proposal — awaiting review and implementation decision.
