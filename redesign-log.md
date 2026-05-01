# Control redesign log

> Living design doc for Control's "essence-first" redesign. Addresses three operator-reported problems with v1.3: complicated to understand, architecture unclear, dense output without narrative. Maintained across implementation cycles — implement, refine, reimplement until the system feels coherent.

**Started:** 2026-05-01
**Current cycle:** 1.5 — full plan locked
**Status:** all design decisions resolved; ready to execute

---

## 1. Problem statement

Three coupled complaints after extended use of Control v1.3:

1. **Complicated to understand.** Surface (11 commands, 5 hooks, 8 templates, 9 config knobs, 4 progress files, 8 HALT conditions) overwhelms readers before the through-line resolves.
2. **Architecture unclear.** Even the maintainer can't articulate Control's architecture without re-reading the 27k-token PROJECT_PROTOCOL.md.
3. **Dense output, no narrative.** Commands emit structured data blocks, not human explanations. The framework "talks to itself about itself, with the operator as a witness, not the audience."

These compound: complexity makes architecture opaque, opaque architecture produces explainer-less output.

**Deeper observation.** Control's job is to help build *complicated* systems. Control itself has become complicated. The redesign's north star is therefore not "fix UX" but "**Control should feel simple even when it's managing complex projects.**" A new operator should be productive after 200 words, not 27,000 tokens.

---

## 2. Design principles

These guide every change. Violations are blockers, not tradeoffs.

- **All invariants stay.** Drift detection (mechanical), regression-test gating, severity gating, commit-shape enforcement, phase tags. Simplification must not weaken any.
- **Collapse the surface, not the discipline.** Discipline can be invisible to the operator and still operative. Reduce the user-facing surface; keep the enforcement layer rich.
- **Narrative before data.** Default output is plain English. Structured data is shown only when (a) drift/blocker/halt demands attention, or (b) operator asks (`--verbose` or "show me the status block").
- **Hook output is for Claude, not the operator.** Hooks emit machine-readable status; Claude reads it and *narrates* to the operator. Hook prose should not appear directly in the operator's terminal.
- **One file, one job.** Where two files overlap (e.g., `spec/SPEC.md` + `architecture/overview.md`), pick one and merge.
- **Production over preservation.** When a piece of v1.3 machinery exists for a defunct reason, delete it, don't soften it. Aliases for one minor version, then gone.

---

## 3. Control's essence — the new opening

Lead README.md and PROJECT_PROTOCOL.md with this:

> **Problem.** AI sessions are stateless; software projects are stateful.
>
> **Core.** STATE.md is the single working file Claude reads at session start and overwrites at session end. Git is the permanent record (commits per step, tags per phase). Snapshots are the recovery layer.
>
> **The five invariants Control enforces:**
> 1. Read STATE.md first, every session.
> 2. Commit per step — git log is the narrative.
> 3. Tag per phase — rollback works.
> 4. Update STATE.md atomically at session end.
> 5. Detect drift mechanically — never trust LLM self-report.
>
> Everything else — commands, templates, hooks, ADRs, issues, autonomy stages, config — is machinery enforcing these five invariants.

---

## 4. Architecture (canonical, single diagram)

```
        STATE.md  ← single source of truth (working memory)
        ↑      ↓
     reads   writes
        │      │
     slash    hooks (PreCompact / SessionStart / SessionEnd / Stop)
     commands  │
        │      │
        └─ git log + tags ─┘   (permanent record)
                  │
                  └── snapshots (recovery)
```

**Three layers, that's it:**
- **Working memory** — `.control/progress/STATE.md`. Overwritten at every session end.
- **Permanent record** — git history. Commits = step narrative. Tags = phase boundaries.
- **Recovery** — snapshots. PreCompact saves before context compaction; Stop checkpoints between turns; SessionEnd records the close.

Every Control operation updates exactly one of these three layers atomically. Nothing else has authority.

---

## 5. Output shape — the new contract

Default output for any status-emitting command (`/session-start`, `/work-next`, `/phase-close`):

> **Continuing Phase 2 (DSPy QueryPlanner), step 2.3.**
> Last session implemented 2.2 base classes (`abc123`). Working tree clean, no blockers, last test green.
>
> **Next:** define QueryPlanner signature per spec §3.2.
>
> Ready?

Verbose mode (`--verbose` flag OR operator says "show status block" / similar):

```
Phase 2 — DSPy QueryPlanner, step 2.3
Last action: 2.2 base classes — abc123 feat(2.2): scaffold ...
Git: branch=main, last=abc123 ..., uncommitted=no, tag=phase-1-foundation-closed
Git sync: ✓ matches STATE.md
Open blockers: None
Test/eval status: 47/0 (last run 2026-04-29)
Proposed next action: define QueryPlanner signature per spec §3.2
```

Drift, blockers, or halt conditions force structured-block display. Otherwise narrative wins.

**Errors:** narrate first (1-2 sentences), then show error details. Never suppress.

**Hook output format.** Markdown heredoc, data-only blocks. No instruction prose. Format:

```
[control:state]
branch: <name>
last-commit: <sha> <subject>
working-tree: clean | dirty
last-tag: <tag>
state-md-status: in-sync | drift-detected
[/control:state]

[control:drift]            (only when drift detected)
field: <name>
expected: <state-md-value>
actual: <git-value>
[/control:drift]

[control:recommendation]   (when SessionStart asks for one)
priority: <1-6, per work-priority.md>
action: <concrete next action>
[/control:recommendation]
```

Claude reads these blocks and narrates. Operator never sees `[control:*]` blocks unless `--verbose`.

---

## 6. Change set — cycle 1

Grouped by risk. A is lowest risk (docs only). C is highest (architecture).

### Group A — Docs (Problem 1 + 2; low risk)

| ID | Change | Files |
|---|---|---|
| A1 | Add "Control in 60 seconds" cover section (essence + architecture + 5 invariants) at top of both docs | `README.md`, `.control/PROJECT_PROTOCOL.md` |
| A2 | Terminology pass: "step" everywhere, no "sub-step." Two levels (phase, step), not three. The commit format `<type>(<phase>.<step>)` is the canonical name | `CLAUDE.md`, `.control/PROJECT_PROTOCOL.md`, `README.md`, `.claude/commands/*.md`, `.control/runbooks/*.md` |
| A3 | Clarify journal vs commit log vs ADR roles in one explainer table | `.control/PROJECT_PROTOCOL.md` |
| A4 | Re-order README sections: essence → architecture → invariants → install → daily workflow → reference. Currently install comes before essence | `README.md` |

### Group B — Output (Problem 3; medium risk)

| ID | Change | Files |
|---|---|---|
| B1 | Two-layer output convention (see §5). Update commands so default is narrative; structured block on `--verbose` or attention-demanding events | `.claude/commands/session-start.md`, `work-next.md`, `phase-close.md`, `control-next.md`, `validate.md` |
| B2 | Hook output emits *data*, not instructions. Drop the "Before accepting user input, run protocol: 1. Read STATE.md..." heredoc — that's command-file territory. Hook just emits structured `[control:*]` blocks; Claude narrates from `.claude/commands/session-start.md` | `.claude/hooks/session-start-load.{sh,ps1}` |
| B3 | Drift surfacing: when drift detected, Claude narrates ("STATE.md says branch=foo but actual is main — sync before proceeding?"), not raw `[DRIFT]` lines pasted at operator | `.claude/commands/session-start.md` runbook + hook output protocol |
| B4 | Single canonical status-block shape, used by all status-emitting commands. Currently slightly different between `/session-start`, `/work-next`, `/phase-close` | `.control/runbooks/session-start.md`, `session-end.md` |

### Group C — Surface consolidation (Problem 1; higher risk, one ID per cycle)

| ID | Change | Files | Risk |
|---|---|---|---|
| C1 | Merge `/control-next` into `/session-start`. Make `/session-start` idempotent — re-running mid-session re-prints status + recommendation. Move priority logic to `.control/runbooks/work-priority.md`. Leave `/control-next` as deprecated alias for v2.0; remove in v2.1 | `.claude/commands/session-start.md`, `.claude/commands/work-next.md`, `.claude/commands/control-next.md` (alias), `.claude/hooks/session-start-load.{sh,ps1}`, new `.control/runbooks/work-priority.md` | Recently shipped in v1.4; resolved via alias-then-remove |
| C2 | Collapse spec layout: `.control/spec/SPEC.md` + `artifacts/` + `architecture/overview.md` → single `.control/SPEC.md`. Spec evolution lives in git history. Add `/spec-amend` (appends a dated section); keep `/new-spec-artifact` as alias | `.control/spec/`, `.control/architecture/overview.md`, `.claude/commands/bootstrap.md`, `.claude/commands/new-spec-artifact.md` (alias), new `.claude/commands/spec-amend.md`, `setup.sh`/`setup.ps1` w/ migration | Touches install path; setup.sh `--migrate-spec` handles existing installs |
| C3 | `next.md` becomes auto-generated from STATE.md at SessionEnd (templated extract of "Notes for next session" + "Next action"); operator never writes by hand. Cross-tool handoff use case preserved | `.claude/hooks/session-end-commit.{sh,ps1}`, `.claude/commands/session-end.md` | Behavior change; smoke-tested in scratch-install |
| C4 | `/validate` becomes a SessionStart-time auto-check. Output surfaced only when issues found. Manual `/validate` stays as alias | `.claude/hooks/session-start-load.{sh,ps1}`, `.claude/commands/validate.md` | Cheap; adds small hook latency |
| C5 | Source-repo sentinel: `.control/.is-source-repo` (gitignored). SessionStart hook checks for it; if present, suppresses the `[DRIFT] STATE.md is in template form` line. For this repo: manually create the sentinel. For future forks: setup.sh prompts during install | `.claude/hooks/session-start-load.{sh,ps1}`, `setup.sh`/`setup.ps1`, `.gitignore` | Source-repo only; consumer projects unaffected |

### Group D — Invariants kept, better-explained (no behavior change)

Pure documentation, embedded into the new essence section:
- Drift detection — explain WHY it's mechanical (LLM can't be trusted to verify itself)
- commit-msg hook — explain it as the "git log narrative" enforcer
- Severity-gated issues — cost/benefit (minor: cheap journal line; major: file + regression gate)
- Phase tags — `git reset --hard phase-N-closed` is the recovery primitive

### Snapshot pool unification (D-tier, included in C cycle)

Unify the two snapshot retention pools into one with type-prefix in filenames (`precompact-*.md`, `stop-*.md`, `sessionend-*.md`). One prune script handles all with type-specific retention budgets. Lands during cycle 5 alongside relevant hook changes.

---

## 7. Out of scope (cycle 1)

Explicit non-goals to prevent scope creep:
- New autonomy stages (stage 3 = unattended)
- Migrating away from bash/PowerShell hooks
- Web/GUI front-end (Control is CLI-shaped)
- Replacing git as the persistent layer
- Multi-project coordination
- Splitting `/bootstrap` into spec-mode and scan-mode commands (revisit in v2.1)
- Plugin model for future Claude Code hook events
- `/clear` mid-session handling (defer to v2.1 if it becomes a real problem)
- Team / multi-operator workflows

---

## 8. Anti-goals (regressions to prevent)

- Don't weaken drift detection — it's the trust anchor.
- Don't make Control depend on a runtime other than git + bash/PS.
- Don't reintroduce LLM-driven verification of state. Always mechanical.
- Don't break `UPGRADE=1` for installed projects mid-cycle. Migration paths must be tested before merging.
- Don't widen the surface in service of "discoverability." Discoverability comes from the cover section, not more commands.

---

## 9. Resolved decisions

Each: question, options, decision, reason. Recorded so future-Claude can re-derive the choices.

### Strategic

| ID | Decision | Reason |
|---|---|---|
| **D1** | Version target: **v2.0** | Reframing changes operator-facing semantics; v2.0 sets correct expectations |
| **D2** | Audience: **solo dev** | Control's command-and-hooks shape assumes one operator; multi-operator needs new mechanisms (locks, conflict resolution) — out of v2.0 scope |
| **D3** | Backward compat: **best-effort with migration helpers** | Strict prevents real surface collapse; breaking is operator-hostile. setup.sh `--migrate-spec` handles consolidation atomically with operator confirmation |
| **D4** | `improvement.md` fate: **fold + archive** | v1.4 has real ideas (filled examples, doc-layers section) worth preserving; archiving keeps thinking accessible |
| **D5** | Doc rewrite scope: **add cover + restructure body** | Rewrite loses reference value; cover-only doesn't fix "reader gets lost in body" |

### Surface

| ID | Decision | Reason |
|---|---|---|
| **D6** | `/control-next`: **alias for v2.0, remove in v2.1** | Muscle memory + v1.4 just shipped this; one minor of grace is fair |
| **D7** | `next.md`: **auto-generate from STATE.md at SessionEnd** | Serves cross-tool handoff (paste into Claude.ai web); deleting loses functionality; manual is redundant with STATE.md |
| **D8** | `architecture/overview.md`: **delete; SPEC.md is canonical** | PROJECT_PROTOCOL.md already says "spec wins over distilled docs" — overview is the distillation that loses; eliminating removes drift surface |
| **D9** | `/new-spec-artifact`: **add `/spec-amend`, keep old as alias for v2.0** | Spec layout collapse means "artifacts/" doesn't exist — old name is misleading |
| **D10** | Snapshot pool: **unify with type-prefix in filename** | Only reason for two pools was different prune logic; type-prefix lets one script handle all with type-specific retention |

### Implementation

| ID | Decision | Reason |
|---|---|---|
| **D11** | Branch: **`redesign-v2`, merge cycle-by-cycle** | Main stays usable, merges stay reviewable |
| **D12** | Commit format: **`redesign(<group>.<id>): <subject>`** | Control's canonical format doesn't apply (we're not in a Control phase); prefix lets `git log --grep='^redesign'` filter the work. **Pre-flight: read `.githooks/commit-msg`; update to allow `redesign` type if needed** |
| **D13** | Cycle granularity: **mixed** | Low-risk groups (A, D) bundle; high-risk (C) one ID per cycle |
| **D14** | Test target: **gitignored `tests/scratch-install/`** | Reproducible across sessions; survives reboots |
| **D15** | Definition of done: **tag v2.0.0 after all groups land + scratch-install smoke test passes** | v2.0 is incomplete without architecture changes; rc soak is ceremony without users |
| **D16** | Migration guide: **separate `MIGRATION-v1.3-to-v2.0.md`** | One-time concern; cluttering README hurts the new cover section |
| **D17** | Verbose flag: **both `--verbose` AND natural-language ("show me the status block")** | Flag is reliable, NL is forgiving |
| **D18** | Error handling: **narrate first, then show error details** | Errors need actionable info; narrative consistency matters but not at cost of debug data |

### Technical

| ID | Decision | Reason |
|---|---|---|
| **D19** | Hook output format: **markdown heredoc, data-only `[control:*]` blocks (see §5)** | Markdown is easy to write/read; discipline (no instruction prose) gets benefit without parser cost |
| **D20** | Spec layout migration: **detect + prompt + atomic migrate** | Silent is too aggressive; leaving alone creates two-layout drift forever. Migration script consolidates 3 files → 1 with H2 section headers for operator review |
| **D21** | `/clear` mid-session: **skip for v2.0** | No evidence of frequent operator /clear in Control workflows; revisit in v2.1 |
| **D22** | Source-repo sentinel: **`.control/.is-source-repo` (gitignored), checked by SessionStart hook** | Stops daily false-positive `[DRIFT]` line in this repo; no impact on consumer projects |

---

## 10. Investigation items

Not blockers — surface during execution. Adapt if they reveal something unexpected.

| ID | Item | Cycle |
|---|---|---|
| **I1** | Actual constraints of `.githooks/commit-msg` (does it restrict types?) | Pre-flight (cycle 2) |
| **I2** | Format Claude Code's hook system actually accepts from stdout (markdown? JSON only?) | Cycle 4 / Group B start |
| **I3** | Scratch-install behavior on Windows vs Linux paths (this repo is Windows; setup.sh runs in Git Bash) | Cycle 4 |
| **I4** | What `improvement.md` items have already partially shipped vs. only proposed | Cycle 2 |

If any reveals a blocker, pause and surface it. Otherwise execute.

---

## 11. Cycle log

### Cycle 1 — design (DONE)
- 2026-05-01: drafted essence, invariants, architecture diagram, change set, anti-goals
- 2026-05-01: identified open questions

### Cycle 1.5 — decisions locked (DONE)
- 2026-05-01: 22 design decisions resolved (D1–D22 in §9)
- 2026-05-01: full execution plan recorded (§12 below)
- 2026-05-01: investigation items separated from blocker questions (§10)

### Cycle 2 — pre-flight + v1.4 reconciliation (DONE 2026-05-01)
- ✅ Pre-flight: updated `.githooks/commit-msg` to allow `[A-Z](\.N[a-z]?)?` parens (group/ID like `A.1`, `C.5a`) and `reconcile(\.N[a-z]?)?` parens; added `redesign` to CONTROL_COMMIT_TYPES (resolves **I1**). Commit `3f60aa2` on main.
- ✅ Pre-flight: created `redesign-v2` branch from main (after committing redesign-log.md as `c0aad8e`)
- ✅ Skipped CLAUDE.md note: CLAUDE.md is the shipped template (kind=project but visible at root); editing it would either ship "Active redesign" prose to consumer projects (wrong) or be reverted before merge (pointless). redesign-log.md at root is sufficient signal.
- ✅ Read `improvement.md` end-to-end + cross-checked filesystem and `.relay/implemented/` (resolves **I4**). Finding: all 7 improvements + 4 ancillary items shipped between 2026-04-21 and 2026-05-01. No partial-ship state.
- ✅ Verified specific v1.4 items by file inspection: `.control/templates/{adr,issue}-example.md` exist; phase-readme.md has narrative + Deferred sections; PROJECT_PROTOCOL.md has "Documentation layers" section; CLAUDE.md has checkbox-flip discipline.
- ✅ Appended §16 "v1.4 reconciliation" to redesign-log.md mapping each item to KEEP / KEEP+INTEGRATE / SUPERSEDE.
- ✅ Moved `improvement.md` → `archive/improvement-v1.4.md` with prepended ARCHIVED header pointing to redesign-log.md §16.
- **Outcome:** v1.4 is almost entirely ALIGNED with v2.0. Only `/control-next` is being superseded (alias-then-remove per D6). No reverts needed.
- **Surprises:** none. Reconciliation cleaner than expected because v1.4 implementation matches v1.4 proposal closely.

### Cycle 3 — Group A (docs) — DONE 2026-05-01
- ✅ A1 (commit `0d11bf8`): Control-in-60-seconds cover added to README.md and PROJECT_PROTOCOL.md. Cover delivers problem framing + single architecture diagram + 3-layer model + 5 invariants + through-line. Self-review passed; no stop.
- ✅ A2 (commit `afc42cd`): terminology pass — "sub-step" → "step" across 8 files (CLAUDE.md, PROJECT_PROTOCOL.md, README.md, tests/README.md, phase-readme.md, phase-steps.md, phase-plan.md, .githooks/commit-msg). Skipped redesign-log.md and archive/ intentionally.
- ✅ A3 (commit `194b756`): "Operational captures" sub-section added to PROJECT_PROTOCOL.md Documentation layers — 4-row table (git log / journal / ADRs / issues), decision rule of thumb, anti-pattern callout against duplication.
- ✅ A4 (commit `7f5afa6`): README section reorder — "What it gives you" feature catalog demoted from TOC item 1 to item 7 (just before Reference). Cover at top is the lead; catalog is reference.
- **Outcome:** docs now lead with essence; reference follows. Terminology consistent. Capture-mechanism confusion addressed.
- **Surprises:** A4 was smaller than scoped — A1 already did most of the "essence-first" reorder; A4 became "demote the feature catalog and update TOC."

### Cycle 4 — Group B (output layering) — DONE 2026-05-01
- ✅ B.2 (commit `a034e4d`): hook emits structured `[control:state]`, `[control:snapshot]`, `[control:drift]` blocks. 7 drift types catalogued. Tests T3a-h + T7 in tests/i5-parity.sh updated to assert the new format. All 21 tests pass. Resolves **I2** (hook output format Claude Code accepts: markdown heredoc with discipline works fine).
- ✅ B.4 (commit `253e7e0`): canonical narrative + verbose shapes defined in `.control/runbooks/session-start.md` step 5. Verbose forced when drift detected. Same convention added to session-end.md step 6.
- ✅ B.1 (commit `727abe3`): 4 slash commands updated with "Output shape (v2.0)" sections. session-start.md thinned to a 3-bullet pointer at the runbook. work-next/phase-close/validate keep their existing protocol logic plus narrative-default rules.
- ✅ B.3 (commit `e8f0f4d`): drift narration cheat sheet added to runbook step 4 — per-type suggested narration + reconciliation action. "STATE.md is operator-owned" boundary explicit.
- **Smoke test:** ran bash + PS hooks in this repo; output is data-only `[control:*]` blocks + `-> Follow .claude/commands/session-start.md` tail. Parity verified (PARITY OK).
- **Outcome:** end-to-end output layering shipped. Hook = data, slash command = thin contract pointer, runbook = canonical shapes + drift cheat sheet. Commands narrate; verbose on request or drift.
- **Surprises:** PS 5.1 reads .ps1 as Windows-1252 by default, breaking UTF-8 `→` in `powershell -NoProfile -File` invocation — switched both hooks to ASCII `->` for byte-stable parity. Investigation **I3** (scratch-install Windows behavior) deferred to cycle 5 since Group B didn't need a full install round-trip; the hook + runbook + slash command updates were verified in-repo via direct hook invocation.

### Cycle 5 — Group C (architecture, one ID per sub-cycle)
- ✅ **5a (DONE)**: C.5 — source-repo sentinel `.control/.is-source-repo` (commit `28c04b7`). Hook checks for sentinel before any drift detection; suppresses ALL drift if present. Setup scripts prompt on install. New T3i parity test (22/22 pass). Foot-gun removed: this repo no longer emits `state-md-template` drift every session.
- ✅ **5b (DONE)**: C.2 — spec layout collapsed (commit `200efff`). 13 files changed, 465+/-133 lines. Source repo: deleted `.control/spec/`, `.control/architecture/overview.md`, `.control/templates/spec-readme.md`; created `.control/SPEC.md` starter. Setup scripts: removed old layout creation, added v1.3 → v2.0 migration block (interactive, prompts before touching, backs up to `.control.v1.3-backup/`). New `/spec-amend` command, `/new-spec-artifact` deprecated alias. `MIGRATION-v1.3-to-v2.0.md` written. **STOP POINT — surface for operator review.**
- **5c (PLANNED)**: C.3 — auto-generate next.md at SessionEnd
- **5d (PLANNED)**: C.4 — auto-validate at SessionStart (only surface output if issues)
- **5e (PLANNED)**: C.1 + snapshot unification — merge `/control-next` into `/session-start`; move priority logic to `.control/runbooks/work-priority.md`; unify snapshot pool

### Cycle 6 — Group D (better explanations)
- Embed invariant explanations in cover section
- WHY each invariant exists, in `.control/PROJECT_PROTOCOL.md`

### Cycle 7 — final polish + tag
- Update `VERSION` to 2.0.0
- Update setup.sh / setup.ps1 install commit message ("Control framework v2.0.0")
- Run end-to-end smoke test on scratch-install (full session-start → step commit → session-end → next-session round-trip)
- Tag `v2.0.0`
- Merge `redesign-v2` → main
- **Stop point**: surface for operator final approval before tag + merge

### Cycle 8 — re-instantiate Relay
- Per operator request: bring Relay back in to drive future improvements
- Verify `.relay/` structure still compatible with v2.0 layout
- Move v1.4 backlog items still relevant into `.relay/issues/` or `.relay/features/`

---

## 12. Execution plan summary

### Pre-flight (start of cycle 2)
1. Create `redesign-v2` branch from main
2. Add CLAUDE.md note: "Active redesign: see redesign-log.md. Commits use `redesign(<group>.<id>):` not Control's canonical format."
3. Read `.githooks/commit-msg`; update to allow `redesign` type if currently restricted

### Cycle execution (continuous unless stop point hit)

| Cycle | Scope | Stop point |
|---|---|---|
| 2 | v1.4 reconciliation | If v1.4 has partially-shipped items needing different handling |
| 3 | Group A (docs) | If A1 cover wording feels off |
| 4 | Group B (output) | If hook output format (I2) blocks |
| 5a | C5 (source-repo sentinel) | None |
| 5b | C2 (spec collapse + migration) | Migration script ready for operator review |
| 5c | C3 (next.md auto-gen) | None |
| 5d | C4 (auto-validate) | None |
| 5e | C1 + snapshot unification | None |
| 6 | Group D (better explanations) | None |
| 7 | Polish + v2.0.0 tag | Final approval before tag + merge to main |
| 8 | Re-instantiate Relay | None |

### Stop conditions (will pause for operator)
- Any cycle's stop point above
- Smoke test fails on scratch-install at cycle close
- Any change in Group C surfaces a regression in Groups A or B
- Any investigation item (I1–I4) surfaces a blocker
- Any time the change feels wrong; pause and surface

Otherwise: execute continuously.

---

## 13. Migration strategy (v1.3 → v2.0)

For consumer projects already on v1.3:

```bash
# Operator runs:
UPGRADE=1 bash control/setup.sh
```

setup.sh detects and acts:
- **3-file spec layout** (`.control/spec/SPEC.md` + `.control/spec/artifacts/` + `.control/architecture/overview.md`) → triggers spec-layout migration prompt; consolidates atomically into `.control/SPEC.md` with H2 section headers (`## Spec` / `## Artifacts (chronological)` / `## Overview`) for operator review; commits as `chore: migrate spec layout to v2.0`
- **Hand-written `next.md`** → no destructive action; auto-generation kicks in at next SessionEnd
- **`.claude/commands/control-next.md`** → leaves alias in place; tells operator "deprecated in v2.0, removal in v2.1"
- **Two snapshot pools** → reformats `prune-snapshots.sh` to unified-pool logic; existing snapshots get type-prefix added on first prune
- **No `.control/.is-source-repo`** → asks "Is this the Control source/dev repo?" If yes, creates the sentinel and adds to `.gitignore`

Migration commit format: `chore: migrate to Control v2.0 layout`. Separate from any operator-driven work.

`MIGRATION-v1.3-to-v2.0.md` ships with v2.0 and documents:
- What changed (link to redesign-log.md §6)
- What's automatic (auto-migration via setup.sh)
- What's manual (operator review of consolidated SPEC.md)
- Rollback (git tag `pre-v2-migration` set by setup.sh before any change; `git reset --hard pre-v2-migration` reverts)

---

## 14. Implementation hygiene

- Each cycle gets its own commit set. One commit per change ID where practical.
- Commit format: `redesign(<group>.<id>): <subject>` — e.g., `redesign(A.1): add Control-in-60-seconds cover section`. The commit-msg hook (.githooks/) must allow `redesign` as a type — verify pre-flight.
- After each cycle, update §11 cycle log with: what shipped, what surprised us, what got punted, what got reverted.
- Run all changes through `tests/scratch-install/` before marking a cycle closed.
- Investigation items (§10) get resolved inline as cycles surface them. Mark `**Resolved cycle N**: <answer>` rather than deleting.
- If a decision turns out wrong mid-cycle, revert the commits, update §9 with the new decision and reason, restart the cycle.

---

## 15. What "done" looks like

v2.0.0 is shippable when:

- [ ] All Group A changes merged (cover sections, terminology, README reorder)
- [ ] All Group B changes merged (narrative output, hook data-only, drift narration, canonical status block)
- [ ] All Group C changes merged (sentinel, spec collapse, next.md auto-gen, auto-validate, control-next merge, snapshot unification)
- [ ] All Group D changes merged (invariant explanations)
- [ ] `MIGRATION-v1.3-to-v2.0.md` written and reviewed
- [ ] setup.sh / setup.ps1 `--migrate-spec` works on a v1.3 fixture
- [ ] `tests/scratch-install/` round-trip passes (install → /session-start → step commit → /session-end → /session-start sees prior state)
- [ ] `tests/i5-parity.{sh,ps1}` still passes (bash/PS hook output still byte-equivalent)
- [ ] `VERSION` = 2.0.0
- [ ] `git tag v2.0.0` set
- [ ] redesign-v2 merged to main
- [ ] redesign-log.md cycle log updated with final state

---

## 16. v1.4 reconciliation

The v1.4 proposal (`improvement.md`, archived 2026-05-01 to `archive/improvement-v1.4.md`) shipped between 2026-04-21 and 2026-05-01 ahead of this redesign. This section maps each v1.4 item to its v2.0 disposition.

**Verification method:** filesystem checks against `.control/templates/`, `.control/PROJECT_PROTOCOL.md`, `CLAUDE.md`, `.claude/commands/`, plus cross-reference to `.relay/implemented/`.

### Improvements proposed in v1.4 (all shipped)

| v1.4 improvement | Status in v1.4 | v2.0 disposition | Reason |
|---|---|---|---|
| 1. Filled ADR example | SHIPPED (`.control/templates/adr-example.md` exists) | KEEP | Aligns with v2.0 principle of "ship better starting points" |
| 2. Filled issue example | SHIPPED (`.control/templates/issue-example.md` exists) | KEEP | Same as above |
| 3. Phase README narrative ("Where we were", "Why this phase exists") | SHIPPED (`.control/templates/phase-readme.md` lines 12–26) | KEEP | Aligns with v2.0 |
| 4. Forward-pointers ("Deferred to Phase N+1") + /phase-close auto-carry | SHIPPED (phase-readme.md lines 49–56; `.relay/implemented/phase_close_auto_carry.md`) | KEEP | Aligns |
| 5. Long-form progress ack + Documentation layers section | SHIPPED (`PROJECT_PROTOCOL.md` §"Documentation layers" line 956+; session-end runbook reference) | KEEP + INTEGRATE | Doc layers section coexists with new essence cover. Cover answers "what is Control"; doc layers answers "where do project docs live". Both useful. |
| 6. Steps checklist sync discipline | SHIPPED (CLAUDE.md "Flip the checkbox in the same commit" invariant) | KEEP | A2 terminology pass changes "sub-step" → "step" but discipline stays |
| 7. /control-next command | SHIPPED (`.claude/commands/control-next.md`; chained from /session-start) | **SUPERSEDE** | Per D6: kept as deprecated alias for v2.0, removed in v2.1. /session-start absorbs the priority logic (cycle 5e / C1) |

### Ancillary v1.4 work (in `.relay/implemented/`, not in improvement.md)

| Item | Status | v2.0 disposition |
|---|---|---|
| Drift detection mechanical (`drift_detection_llm_dependent`) | SHIPPED | KEEP — aligns with v2.0 anti-goal "always mechanical" |
| PreCompact hook fix (`precompact_hook_mutates_journal`) | SHIPPED | KEEP — no change |
| Stop hook overwrite fix (`stop_hook_overwrite_not_rolling`) | SHIPPED | KEEP, REVISIT in cycle 5e — D10 unifies the two snapshot pools, so the rolling Stop snapshot pool gets folded into the unified pool. Semantic stays; storage layout changes. |
| Windows PowerShell hook parity (`windows_powershell_hook_parity`) | SHIPPED | KEEP — no change. v2.0 work that touches `.sh` hooks must touch matching `.ps1` siblings. |

### Items v2.0 will revisit

Only one v1.4 item is being modified:

- **`/control-next`** — kept as deprecated alias in v2.0 per D6, removed in v2.1. The chaining-from-/session-start pattern (currently a runbook step) becomes built-in to /session-start.
- **Stop hook / snapshot pool** — pool unification (D10) folds the two retention pools into one with type-prefixed filenames. The fix from v1.4 (rolling Stop snapshots) stays semantically; only the storage layout changes.

### Net reconciliation

v1.4 is mostly **ALIGNED** with v2.0. The bulk of v1.4 (filled examples, narrative phase sections, deferred + auto-carry, doc layers, steps-checklist discipline, drift detection, PowerShell parity) stays as-is.

v2.0 layers on top:
- Essence cover section (§3, Group A1) — new abstraction layer above the v1.4 doc layers section
- Narrative output (Group B) — replaces structured-block-by-default behavior
- Surface consolidation (Group C) — collapses spec layout, deprecates /control-next, auto-generates next.md, adds source-repo sentinel, unifies snapshot pools

No v1.4 work is being reverted. The proposal doc is archived (not deleted) at `archive/improvement-v1.4.md`.

**Resolved:** I4 ("What v1.4 items have already partially shipped vs only proposed"). Answer: **all 7 improvements + 4 ancillary items shipped between 2026-04-21 and 2026-05-01.** No partial-ship state to handle.
