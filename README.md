```
  ██████╗   ██████╗   ███╗   ██╗ ████████╗ ██████╗    ██████╗   ██╗
 ██╔════╝  ██╔═══██╗  ████╗  ██║ ╚══██╔══╝ ██╔══██╗  ██╔═══██╗  ██║
 ██║       ██║   ██║  ██╔██╗ ██║    ██║    ██████╔╝  ██║   ██║  ██║
 ██║       ██║   ██║  ██║╚██╗██║    ██║    ██╔══██╗  ██║   ██║  ██║
 ╚██████╗  ╚██████╔╝  ██║ ╚████║    ██║    ██║  ██║  ╚██████╔╝  ███████╗
  ╚═════╝   ╚═════╝   ╚═╝  ╚═══╝    ╚═╝    ╚═╝  ╚═╝   ╚═════╝   ╚══════╝

phased session-management for ai coding
every step a commit, every phase a tag, drift detected mechanically
```

[![Version](https://img.shields.io/npm/v/control-workflow?style=flat-square&color=blue)](https://www.npmjs.com/package/control-workflow)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D18-brightgreen?style=flat-square&logo=node.js)](https://nodejs.org)
[![Claude Code](https://img.shields.io/badge/Claude_Code-Hooks%20%2B%20Commands-blueviolet?style=flat-square)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)

Control is a phased session-management framework for building software with AI in Claude Code. You direct the strategy — what phases to ship, what done means, when to close. Claude executes within mechanical bounds — every step closes with a commit (typed via `<type>(<phase>.<step>): <subject>`), every phase closes with a tag, every session begins with a field-by-field drift check between `STATE.md` and git reality. A persistent `.control/` layer holds the operational state — STATE.md (current cursor), phases/, issues/, ADRs — so resumed sessions never start from zero. Works with **Claude Code**.

## The Problem

Multi-session software development with AI has three structural failure modes:

- **State amnesia** — every session starts from zero. The agent doesn't remember what was decided yesterday, what step is mid-flight, or whether `STATE.md` still matches git. You re-explain the project on every cold start.
- **Untracked progress** — work spreads across days and operators. "What did Claude do yesterday?" needs the whole log scanned. There's no canonical cursor saying "we're on step 2.3, blocker on issue #4, next is phase-close."
- **Silent drift** — the agent's mental model of the project drifts from reality. A spec it wrote turn 3 contradicts the code it wrote turn 17. `STATE.md` says branch=main but you're on a feature branch. By the time you notice, the divergence has compounded across sessions.

The bigger the project, the worse it gets. You re-explain architecture, re-derive next steps, lose the thread of multi-session efforts, and burn cycles on work that's already been done — or worse, undo it.

### When to use Control

✅ **Use it when:**

- The project will span multiple sessions over weeks or months
- You have ≥3 distinct phases (design → implement → test → ship, or domain equivalents)
- You're making architectural decisions you want to preserve as ADRs
- Multiple operators (or multiple AI sessions across days) will work on the project
- You want autonomous AI work with safety rails (HALT conditions, regression-test gates, mechanical drift detection)

❌ **Skip it when:**

- One-shot fix or weekend spike
- Single-session feature
- The overhead (~20 files of process scaffolding + invariants to follow) outweighs the project's expected lifespan

**Hard requirement:** the project must be a git repo. Control depends on commits per step and tags per phase. No git = no rollback, no narrative, no protocol. `git init` before anything else.

## The Solution

Control is a **discipline layer for AI coding**. Five mechanical invariants prevent drift before it starts.

**Architecture (the only diagram you need):**

```
        STATE.md   ← single source of truth (working memory)
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

**Three storage layers — every operation updates exactly one, atomically:**

- **Working memory** — `.control/progress/STATE.md`. Overwritten at every session end. Single source of truth.
- **Permanent record** — git history. Commits = step narrative. Tags = phase boundaries. Rollback = `git reset --hard phase-N-closed`.
- **Recovery** — snapshots. PreCompact saves before context compaction; Stop checkpoints between turns; SessionEnd records the close.

**The five invariants Control enforces:**

1. **Read STATE.md first**, every session.
2. **Commit per step** — git log is the narrative.
3. **Tag per phase** — rollback works.
4. **Update STATE.md atomically** at session end.
5. **Detect drift mechanically** — never trust LLM self-report.

Everything else — slash commands, hooks, templates, ADRs, issues, autonomy stages, config knobs — is **machinery enforcing these five invariants**. Understand STATE.md + the three layers + the five invariants, and you understand Control.

### Severity-gated issues

`minor` → journal line only (cheap). `major` / `blocker` → file in `.control/issues/OPEN/` + regression-test gate at `/close-issue`. The cost matches the stake.

### Both bash and PowerShell hooks ship

Hooks come in twin runtimes (`*.sh` + `*.ps1`). The installer detects bash; if absent, it wires PowerShell hook ports. Both produce byte-equivalent output (verified by `tests/i5-parity.{sh,ps1}` in the source repo).

---

## Table of contents

1. [Why these invariants](#why-these-invariants) — failure mode each one prevents
2. [Quickstart](#quickstart) — install + first session in 5 minutes
3. [Installation](#installation) — install, upgrade, uninstall, runtime detection
4. [Daily workflow](#daily-workflow) — start/end sessions, autonomous mode, issues, ADRs, spec amendments, phase close, handoff
5. [Output: narrative-default, verbose-on-request](#output-narrative-default-verbose-on-request)
6. [Recovery](#recovery) — compaction, botched STATE, phase rollback, source-repo sentinel
7. [Slash commands reference](#slash-commands-reference)
8. [Hooks reference](#hooks-reference)
9. [Configuration (`.control/config.sh`)](#configuration-controlconfigsh)
10. [File structure](#file-structure)
11. [Validation & troubleshooting](#validation--troubleshooting)
12. [Migration from v1.3](#migration-from-v13)
13. [Platform notes](#platform-notes)
14. [Design philosophy](#design-philosophy)
15. [Roadmap](#roadmap)
16. [License](#license)

---

## Why these invariants

Each invariant prevents a specific failure mode. Knowing the WHY helps you decide when to bend the rule (rarely) versus hold the line (usually).

| Invariant | Failure mode it prevents | Why this solution |
|---|---|---|
| **1. Read STATE.md first** | Cold-start sessions re-derive state from scratch; operators waste time re-explaining | A single overwritten file beats a log to scan; single source of truth eliminates "which doc is current?" guesswork |
| **2. Commit per step** | "WIP" commits hide what changed when; bisect becomes useless; rollback is all-or-nothing | Each commit = one verifiable unit. `commit-msg` hook enforces `<type>(<phase>.<step>):` shape so the log stays clean even when authors get sloppy |
| **3. Tag per phase** | Phase boundaries invisible; rollback needs SHAs not names | `git reset --hard phase-3-foo-closed` is the recovery primitive — phase rollback is one command |
| **4. Atomic STATE.md update** | Half-updated STATE.md from a crashed session; split-brain between STATE and derived files | `/session-end` updates every field in one commit. Hooks regenerate derived artifacts (next.md from STATE.md). Either you committed coherent STATE.md or you didn't |
| **5. Mechanical drift detection** | Asking Claude "does STATE.md match reality?" is asking the agent that wrote it to grade its own work | `.claude/hooks/session-start-load.{sh,ps1}` does field-by-field comparison vs `git status` / `git log` / `git describe` BEFORE Claude reads anything. Claude can't ignore the signal — it's data in the prompt context |

**Bonus invariant: severity-gated issues.** `minor` → journal line only (cheap). `major`/`blocker` → file in `.control/issues/OPEN/` + regression-test gate at `/close-issue`. The cost matches the stake. Configurable via `CONTROL_ISSUE_FILE_REQUIRED_FOR` and `CONTROL_ISSUE_JOURNAL_ONLY` in `.control/config.sh`.

---

## Quickstart

5 minutes from "haven't installed Control" to "Claude is working on step 1.1."

```bash
# 1. Install Control into your project
cd ~/projects/my-project
npx control-workflow init

# 2. In Claude Code, bootstrap from your spec (if you have one)
/bootstrap docs/spec.md

# 3. Start working
/session-start
```

**What happens:**

- Control's framework files land in `.control/`, `.claude/`, root-level `CLAUDE.md`, `.control/PROJECT_PROTOCOL.md`
- Git is initialized if not already; commit + `protocol-initialised` tag placed
- Hook runtime auto-detected: bash on PATH → bash hooks; else PowerShell ports
- The installer asks "Is this the Control source/dev repo?" — answer **N** for normal projects (Y only for forks of Control itself)
- `/bootstrap` reads your spec, populates `.control/SPEC.md`, scaffolds Phase 1, sets STATE.md cursor to step 1.1
- `/session-start` reports project state from the structured hook output, recommends next action, waits for go

**No spec yet?** Run `/bootstrap` with no arguments — Claude scans your codebase + interviews you to draft one.

**Requires:** Node.js 18+ and Git. (Node ships everywhere npx does.)

---

## Installation

### Install

```bash
cd ~/projects/my-project
npx control-workflow init                 # install into current dir
npx control-workflow init /path/to/proj   # install into a different dir
```

**Result:**

```
~/projects/my-project/
├── CLAUDE.md
├── .control/         <- Control-managed: progress, phases, issues, SPEC, etc.
├── .claude/          <- Control-managed: commands + hooks
├── .githooks/        <- commit-msg shape enforcement
├── .git/             <- initialized if it wasn't
├── docs/             <- UNTOUCHED: your project's own docs live here
└── (your code)
```

The installer detects existing `.git/` and skips `git init`. Your existing history and branches are preserved.

### Upgrade

```bash
npx control-workflow upgrade
```

**Upgrade refreshes** (`kind=framework` files): `.control/VERSION`, `.claude/commands/*.md`, `.claude/hooks/*.{sh,ps1}`, `.control/runbooks/*.md`, `.control/templates/*.md`, `.control/PROJECT_PROTOCOL.md`, `.githooks/commit-msg`.

**Upgrade leaves alone** (`kind=project` files): `.control/config.sh`, `CLAUDE.md`, `.control/progress/*`, `.control/SPEC.md`, `.control/architecture/phase-plan.md`, `.control/phases/*`, `.control/issues/*`, `.control/architecture/decisions/*`.

`.claude/settings.json` is regenerated to match the operator's `CONTROL_HOOK_RUNTIME` choice (preserved from initial install).

**v1.3 → v2.0 upgrade prompts an interactive spec-layout migration.** See [Migration from v1.3](#migration-from-v13) below.

### Uninstall

```bash
npx control-workflow uninstall            # asks for confirmation
npx control-workflow uninstall --force    # skip confirmation
```

**Removes:** `.control/`, `.claude/settings.json`, all 6 hook scripts (× 2 runtimes), all command files, `.control/PROJECT_PROTOCOL.md`, `CLAUDE.md` (only if it still has the `<!-- control:managed -->` marker), and the Control block from `.gitignore`. Reverts `core.hooksPath` only if it was `.githooks` (set by Control).

**Leaves:** `docs/` (your project docs), all git history and tags, all your code.

### Hook runtime detection

On install, the CLI runs `bash -c 'exit 0'`. If bash works, hooks are wired as `bash .claude/hooks/<name>.sh`. Otherwise PowerShell hook ports (`.claude/hooks/*.ps1`) are wired as `powershell -NoProfile -File .claude/hooks/<name>.ps1`. Both runtimes ship in every install; both produce byte-equivalent output (verified by `tests/i5-parity.{sh,ps1}` in the source repo).

To switch later: edit `CONTROL_HOOK_RUNTIME=bash|powershell` in `.control/config.sh`, then re-run `npx control-workflow upgrade`.

### Dirty working tree

If your working tree is dirty when you install, the installer includes those changes in the install commit. To avoid this, stash or commit first:

```bash
git status
git stash
npx control-workflow init
git stash pop
```

---

## Daily workflow

The transcripts below are illustrative — operator types in plain text or slash commands; Claude responds in v2.0's narrative-default output (full structured blocks shown only on request or when drift demands attention).

### G. First session after install

Two paths depending on whether you already have a written spec/PRD/design doc.

#### G1. Fast path — `/bootstrap` from a spec (recommended when you have one)

Drop your spec at the project root, then in Claude Code:

```
You:    /bootstrap docs/PRD.md
Claude: Read 47 sections from PRD.md. Confirming:
        Project name: Loom
        Phases (proposed):
          1. foundation (auth, data layer)
          2. agent-orchestrator (DSPy + tool use)
          3. analyst (query → SQL → chart)
          4. ingestion-pipeline (CSV/JSON sources)
          5. eval-harness (regression + scoring)
          6. ship (Docker + deploy docs)
        Look right? Any phases to merge or split?

You:    Phase 4 should split into 4a (ingest) and 4b (transform).

Claude: Adjusted phase plan. Populated:
          CLAUDE.md (4 invariants extracted)
          .control/SPEC.md (canonical spec)
          .control/architecture/phase-plan.md (6 phases incl. 4a/4b)
          .control/phases/phase-1-foundation/{README.md,steps.md}
          .control/progress/STATE.md (cursor → Phase 1, step 1.1)
        Committed: chore: bootstrap Loom project docs from PRD.md

        Run /session-start to begin Phase 1.
```

#### G2. Manual path — fill the templates yourself

If you don't have a spec, or prefer to write the scaffolding by hand:

1. **`CLAUDE.md`** — replace `<PROJECT_NAME>`; add project-specific invariants under `## Invariants`.
2. **`.control/SPEC.md`** — fill the Overview, Problem statement, Scope, Tech choices, Architecture sections.
3. **`.control/architecture/phase-plan.md`** — enumerate phases (name, dependencies, outcomes).
4. **Scaffold Phase 1:**

   Linux/macOS/Git Bash:
   ```bash
   mkdir -p .control/phases/phase-1-<your-phase-name>
   cp .control/templates/phase-readme.md .control/phases/phase-1-<your-phase-name>/README.md
   cp .control/templates/phase-steps.md  .control/phases/phase-1-<your-phase-name>/steps.md
   ```

   Windows PowerShell:
   ```powershell
   New-Item -ItemType Directory .control\phases\phase-1-<your-phase-name>
   Copy-Item .control\templates\phase-readme.md .control\phases\phase-1-<your-phase-name>\README.md
   Copy-Item .control\templates\phase-steps.md  .control\phases\phase-1-<your-phase-name>\steps.md
   ```

5. Edit both new files with the phase's goal, steps, and done criteria.
6. Update `.control/progress/STATE.md` — set Current phase, Current step, Next action.
7. Commit:

   ```bash
   git add -A
   git commit -m "chore(install): bootstrap project docs and Phase 1"
   ```

8. Run `/session-start` in Claude Code.

> **Why `/bootstrap` is the better path:** it uses Claude's judgment to extract non-obvious invariants, phase ordering, and step detail from a dense spec — work a human would spend 1-2 hours doing by hand. You still review the output; you don't write it from scratch.

### H. Running a single step (semi-auto)

```
You:    /session-start
Claude: Continuing Phase 2 (DSPy QueryPlanner), step 2.3. Last session
        implemented 2.2 base classes (commit abc123). Working tree clean,
        no blockers.

        Next: define the QueryPlanner signature per spec §3.2.

        Recommended next: continue with step 2.3.
        Ready?

You:    go
Claude: [implements step 2.3]
        Step 2.3 done — defined QueryPlanner signature with 3 fields, added
        unit test, all green. Committed feat(2.3): define QueryPlanner
        signature. Step 2.4 next (signature implementation).

You:    /session-end
Claude: Session closed. Steps 2.3 shipped (commit def456). STATE.md +
        journal + next.md updated; commit ghi789.
        Next session: paste .control/progress/next.md to bootstrap.
```

### I. Running autonomously (loop mode)

```
You:    /loop /work-next
Claude: Picking step 2.3 (next unchecked in steps.md). Implementing now.
        ...
        Step 2.3 done — committed feat(2.3). Picking step 2.4.
        ...
        Step 2.4 done — committed feat(2.4). Picking step 2.5.

        [HALT] New ADR needed — step 2.5 requires a chat-agent framework
        choice between DSPy ReAct and LangGraph. Both fit the spec; need
        operator judgment.
        Current step: 2.5
        STATE.md updated. Resume with /work-next or /loop /work-next when
        ready.

You:    /new-adr chat-agent-framework
        [walk through the ADR with Claude]

You:    /loop /work-next       # resumes from step 2.5
```

**Halt conditions** (configured in `CONTROL_HALT_CONDITIONS`):

- New ADR needed (non-trivial architectural choice)
- Blocker with no clear hypothesis
- Ambiguous failing test (multiple plausible fixes)
- Manual smoke test required
- User-acceptance criterion in done criteria
- Secret or credential needed
- Destructive action required
- Iteration budget hit (default 20; tunable via `CONTROL_MAX_AUTO_ITERATIONS`)

### J. Filing a minor issue (journal-only)

```
You:    /new-issue error-message-typo
Claude: Symptom?

You:    error message says "allow" instead of "allowed"

Claude: Severity?

You:    minor

Claude: Fixed inline (src/errors.py:47). Committed fix(2.3): typo in
        ValidationError message. Added journal line. No issue file created
        per minor-severity gating.
```

### K. Filing a major/blocker issue (file + regression test required)

```
You:    /new-issue agent-tool-loop
Claude: Symptom?

You:    DSPy ReAct loops indefinitely on ambiguous queries — we hit max_iters

Claude: Severity?

You:    major

Claude: Created .control/issues/OPEN/2026-05-01-agent-tool-loop.md with
        Symptom + Repro sections filled from your description. Committed.
        Ready to investigate?

You:    yes

Claude: [reads issue file, hypothesises, implements fix, writes regression]
        Hypothesis: ambiguous queries lacked the "ask for clarification"
        tool, so ReAct kept retrying.
        Fix: added clarify() tool to ReAct module. Failing test for the
        ambiguous-query case now passes (regression at
        tests/test_clarify_path.py:42).

You:    /close-issue 2026-05-01-agent-tool-loop
Claude: Verified regression test exists at tests/test_clarify_path.py:42.
        Moved file to .control/issues/RESOLVED/. Committed
        docs(issues): close 2026-05-01-agent-tool-loop. Updated STATE.md
        "Recently completed."
```

> `/close-issue` **refuses** to close a major/blocker without a regression test. This is an enforced gate — don't work around it. The whole point of severity-gated issues is that closing a major bug without a test means the bug comes back.

### L. Writing an Architecture Decision Record (ADR)

```
You:    /new-adr embedding-model-for-chat-recall
Claude: Walking through ADR shape.
        Context — what forces, constraints, recent signal led here?

You:    Need to recall semantically similar prior chats for the agent's
        context-builder. Latency budget is 50ms p95. We have ~10k chats
        in the corpus, growing weekly.

Claude: Decision — what's the choice?

You:    text-embedding-3-small (OpenAI), with bge-small-en-v1.5 as
        fallback if we go fully local.

Claude: Alternatives considered (with reject reasons)?

You:    [provides 3 alternatives + why each was rejected]

Claude: Consequences — positive, negative, follow-up work?

You:    [provides]

Claude: Created .control/architecture/decisions/0003-embedding-model-for-
        chat-recall.md as proposed. Ready to accept?

You:    accept it

Claude: Status changed to accepted. Committed docs(adr): ADR-0003
        embedding model for chat recall. Updated STATE.md "Recent
        decisions" with the new ADR ref.
```

### M. Amending the spec (`/spec-amend`)

When a decision evolves, the spec needs to evolve with it. v2.0+ uses `/spec-amend` to append a dated section to `.control/SPEC.md`'s "## Artifacts (chronological)" heading — newer artifacts win over older content.

```
You:    /spec-amend pivot-central-store
Claude: Walking through spec amendment shape.
        Title?

You:    Centralize state in Postgres + Redis (pivot from Postgres-only)

Claude: Kind? (addendum | pivot | deep-dive | constraint | other)

You:    pivot

Claude: Scope — which canonical section(s) does this touch?

You:    "Tech choices" — was Postgres-only; now Postgres + Redis (Redis
        for hot-cache of agent context).

Claude: Summary, Context, Content, Impact on phase plan?

You:    [provides each]

Claude: Appended ### 2026-05-01: pivot-central-store as H3 subsection
        under SPEC.md "## Artifacts (chronological)". Committed
        docs(spec): SPEC.md amendment 2026-05-01-pivot-central-store --
        Centralize state in Postgres + Redis.
        Updated STATE.md "Recent decisions" with the amendment ref.
        Phase 4b plan adjusted (added Redis-cache-warmup step).
```

### N. Closing a phase

```
You:    /phase-close
Claude: Phase 2 (DSPy QueryPlanner) done criteria check:
        4 of 5 pass. Smoke test (manual: ask Claude "what was last
        quarter's churn?", verify SQL + chart returned) still needs
        human verification.

You:    [runs the smoke test in a separate terminal]
        smoke test passed; chart looked right

You:    /phase-close

Claude: All criteria pass. Tagged phase-2-dspy-queryplanner-closed.
        Phase 3 scaffolded with 5 steps + 1 carry-forward item from
        Phase 2's Deferred section ("query plan caching — surfaced in
        2.6 review"). STATE.md updated. Run /session-end to close out
        today, OR start step 3.1 directly.
```

### O. Session handoff

End of day:

```
You:    /session-end
Claude: Session closed. Steps 3.2 and 3.3 shipped (commits jkl000..mno111).
        STATE.md, journal, and next.md updated; commit pqr222.
        Next session: paste .control/progress/next.md to bootstrap.
```

Next day, fresh Claude Code session in the same project:

```
# Two ways to bootstrap:
# Option 1: SessionStart hook auto-bootstraps (default if hooks installed)
# Option 2: paste .control/progress/next.md content into the new session

You:    /session-start
Claude: Continuing Phase 3 (analyst), step 3.4. Last session shipped 3.2
        and 3.3 (commits jkl000..mno111). Working tree clean, no blockers.

        Next: implement chart-renderer per spec §4.1.
        Recommended next: continue with step 3.4.
        Ready?
```

`next.md` is **auto-generated** in v2.0+ from STATE.md by `.claude/hooks/regenerate-next-md.{sh,ps1}` (called by both `/session-end` and the SessionEnd hook). Don't write it by hand — edit STATE.md to influence the kickoff.

---

## Output: narrative-default, verbose-on-request

In v1.4 and earlier, Control commands emitted structured status blocks at the operator. v2.0 layers narrative on top: hooks emit machine-readable data, Claude reads it, and Claude narrates plain English to the operator. The structured block exists for `--verbose`, for operator request ("show me the status block"), and is auto-shown when something demands attention (drift, blockers, errors).

### Default narrative

```
Continuing Phase 2 (DSPy QueryPlanner), step 2.3. Last session
implemented 2.2 base classes (abc123). Working tree clean, no blockers.

Next: define QueryPlanner signature per spec §3.2.

Recommended next: continue with step 2.3.
Ready?
```

### Verbose (`--verbose` or "show status block")

```
Phase 2 — DSPy QueryPlanner, step 2.3
Last action: 2.2 base classes — abc123 feat(2.2): scaffold ...
Git: branch=main, last=abc123 ..., uncommitted=no, tag=phase-1-foundation-closed
Git sync: matches STATE.md
Open blockers: None
Test/eval status: 47/0 (last run 2026-04-29)
Proposed next action: define QueryPlanner signature per spec §3.2
```

### Drift detected (forces verbose + reconciliation pause)

```
Drift detected: STATE.md says branch=main but actual is redesign-v2.
Likely cause: you switched branches between sessions but didn't update
STATE.md.

[verbose status block shown for full context]

Reconciliation options:
  1. STATE.md is right — switch back to main
  2. Branch switch was intentional — update STATE.md to redesign-v2

Which one?
```

The hook actually emitted:

```
[control:drift]
type: branch-mismatch
expected: main
actual: redesign-v2
[/control:drift]
```

Claude reads that block and narrates the plain-English version above. The operator never sees the raw block (unless they ask).

### How it's wired

- **Hook output** = data only (`[control:state]`, `[control:snapshot]`, `[control:drift]`, `[control:validate]` blocks).
- **Slash command** files (`.claude/commands/*.md`) tell Claude to narrate from the data.
- **Runbooks** (`.control/runbooks/{session-start,session-end}.md`) define the canonical narrative shape + verbose shape + drift narration cheat sheet.
- **Source-repo sentinel** (`.control/.is-source-repo`, gitignored) suppresses drift detection in Control's own dev repo where STATE.md is intentionally template-shaped.

---

## Recovery

### Compaction recovery

The `PreCompact` hook auto-snapshots to `.control/snapshots/` before context compaction runs.

```bash
# Linux / macOS / Git Bash
ls -la .control/snapshots/                              # list snapshots
diff .control/progress/STATE.md .control/snapshots/STATE-<ts>.md   # compare
cp .control/snapshots/STATE-<ts>.md .control/progress/STATE.md     # restore if needed
```

```powershell
# Windows PowerShell
Get-ChildItem .control\snapshots\
Compare-Object (Get-Content .control\progress\STATE.md) (Get-Content .control\snapshots\STATE-<ts>.md)
Copy-Item .control\snapshots\STATE-<ts>.md .control\progress\STATE.md -Force
```

### Botched STATE.md

```bash
# Option 1: roll back to last git commit
git checkout HEAD -- .control/progress/STATE.md

# Option 2: most recent snapshot (bash)
cp "$(ls -t .control/snapshots/STATE-*.md | head -1)" .control/progress/STATE.md
```

```powershell
# PowerShell equivalent
Copy-Item (Get-ChildItem .control\snapshots\STATE-*.md | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName .control\progress\STATE.md -Force
```

### Rolling back a phase

```bash
git reset --hard phase-2-analyst-closed
```

Same command on Windows; git behaves identically. `git reset --hard <tag>` is the recovery primitive — phase rollback is one command.

### Source-repo sentinel (forking Control itself)

If you fork Control to develop your own variant, create the sentinel so the SessionStart hook stops emitting `state-md-template` drift on your dev repo (the source repo's STATE.md is intentionally template-shaped — that's what gets shipped):

```bash
touch .control/.is-source-repo
echo ".control/.is-source-repo" >> .gitignore
```

Or accept the prompt during `npx control-workflow init` ("Is this the Control source/dev repo?" → answer Y).

---

## Slash commands reference

| Command | Purpose |
|---|---|
| `/bootstrap [<spec-file>]` | Derive project-specific content from a spec file, or scan the codebase to draft one. Populates `CLAUDE.md`, `.control/SPEC.md`, phase-plan, Phase 1 scaffold, STATE.md |
| `/session-start` | Bootstrap the session; report status; recommend next action. **Idempotent** — safe to re-run mid-session |
| `/session-end` | Close the session; update STATE.md; regenerate next.md; append journal; commit |
| `/work-next` | Pick and execute the next item per priority rules (see `.control/runbooks/work-priority.md`) |
| `/loop /work-next` | Autonomous loop within a session; halts on HALT conditions |
| `/new-issue <slug>` | Open an issue (severity-gated: minor → journal line; major/blocker → file + regression-test gate) |
| `/close-issue <id>` | Close major/blocker issue (refuses without regression test) |
| `/new-adr <slug>` | Walk through Context / Decision / Alternatives / Consequences → create ADR |
| `/spec-amend <slug>` | Append a dated H3 amendment to `.control/SPEC.md`'s "## Artifacts" section |
| `/phase-close` | Verify done criteria; tag phase; scaffold next phase (with Deferred carry-forward) |
| `/validate` | Sanity-check protocol files (STATE shape, phase paths, ADR numbering, hook wiring) |

**Removed commands (renamed in v2.0, removed in v2.1):**

| Removed | Replacement |
|---|---|
| `/control-next` | `/session-start` (now idempotent; absorbs the priority logic) |
| `/new-spec-artifact` | `/spec-amend` |

---

## Hooks reference

Control wires four Claude Code hook events plus two helper scripts. Both bash and PowerShell ports ship; the installer wires `.claude/settings.json` to the right runtime via `CONTROL_HOOK_RUNTIME` in `.control/config.sh`.

| Event / Script | Files | What it does |
|---|---|---|
| **`SessionStart`** | `.claude/hooks/session-start-load.{sh,ps1}` | Emits `[control:state]` (git snapshot), `[control:snapshot]` (latest PreCompact path), `[control:drift]` (mismatch blocks), `[control:validate]` (cheap fs checks). Suppressed by source-repo sentinel |
| **`SessionEnd`** | `.claude/hooks/session-end-commit.{sh,ps1}` | Snapshots STATE.md / journal.md / next.md; warns if working tree dirty; calls `regenerate-next-md` as safety net; calls `prune-snapshots` |
| **`PreCompact`** | `.claude/hooks/pre-compact-dump.{sh,ps1}` | Snapshots state files before context compaction wipes them from memory |
| **`Stop`** | `.claude/hooks/stop-snapshot.{sh,ps1}` | Per-turn checkpoint of state files; rolling retention (separate budget from PreCompact pool) |
| Helper: prune | `.claude/hooks/prune-snapshots.{sh,ps1}` | Two modes: arg-less (global pool, retention by count + days) or `<bucket> <count>` (per-prefix retention for Stop) |
| Helper: regen next.md | `.claude/hooks/regenerate-next-md.{sh,ps1}` | Reads STATE.md "Next action" + "Notes for next session" sections; writes templated next.md |
| **`commit-msg`** (git-side) | `.githooks/commit-msg` | Enforces `<type>(<phase>.<step>): <subject>` shape at commit time. Wired via `git config core.hooksPath .githooks` during install |

Hook output format (v2.0):

```
[control:SessionStart]

[control:state]
branch: <branch>
last-commit-sha: <sha>
last-commit-subject: <subject>
working-tree: clean | dirty
last-tag: <tag>
[/control:state]

[control:snapshot]
latest-precompact: <path-or-none>
[/control:snapshot]

[control:drift]                  # zero or more, one per drift detected
type: state-md-{missing,template,unparseable}
                                  # or {branch,commit,uncommitted,tag}-mismatch
expected: <value>                 # for *-mismatch types
actual: <value>
[/control:drift]

[control:validate]               # zero or more
severity: warning | error
check: <kebab-name>              # phase-plan-missing, phase-dir-missing, ...
detail: <prose>
[/control:validate]

-> Follow .claude/commands/session-start.md to bootstrap. ...
```

---

## Configuration (`.control/config.sh`)

Sourced by hooks and command runbooks. Tune per project; v2.0 left this `kind=project` (won't be overwritten on UPGRADE).

| Variable | Default | Purpose |
|---|---|---|
| `CONTROL_MAX_AUTO_ITERATIONS` | `20` | Hard cap on `/loop /work-next` iterations per session |
| `CONTROL_HALT_CONDITIONS` | 8 items | Conditions that halt the loop (e.g., `new_adr_needed`, `ambiguous_failing_test`) |
| `CONTROL_COMMIT_FORMAT` | `{type}({phase}.{step}): {subject}` | Commit message shape |
| `CONTROL_COMMIT_TYPES` | `feat fix test docs refactor chore redesign` | Allowed commit types (regex-enforced by `commit-msg` hook) |
| `CONTROL_PHASE_CLOSE_TAG_FORMAT` | `phase-{n}-{name}-closed` | Tag shape |
| `CONTROL_ISSUE_FILE_REQUIRED_FOR` | `blocker major` | Severities that need an issue file + regression test |
| `CONTROL_ISSUE_JOURNAL_ONLY` | `minor` | Severities that only get a journal line |
| `CONTROL_SNAPSHOT_RETENTION_COUNT` | `50` | Max snapshots kept (general pool: PreCompact + SessionEnd) |
| `CONTROL_SNAPSHOT_RETENTION_DAYS` | `14` | Snapshot age cap |
| `CONTROL_STOP_SNAPSHOT_RETENTION_COUNT` | `10` | Separate budget for Stop snapshots (per-turn cadence) |
| `CONTROL_FAIL_ON_HOOK_ERROR` | `true` | Hooks abort on error vs swallow silently |
| `CONTROL_HOOK_RUNTIME` | `bash` | `bash` or `powershell` — which hook ports `.claude/settings.json` invokes |
| `CONTROL_SESSION_START_REPORT` | 7 keys | Documentation hint for session-start status block fields |

---

## File structure

After a fresh install, your project has:

```
your-project/
├── .control/                              # Control-managed; framework + project state
│   ├── VERSION                            # Installed framework version (kind=framework)
│   ├── PROJECT_PROTOCOL.md                # Long-form framework reference
│   ├── config.sh                          # Tunables (kind=project; UPGRADE-safe)
│   ├── SPEC.md                            # Canonical project spec (kind=project)
│   ├── progress/                          # Operational state (kind=project)
│   │   ├── STATE.md                       # ⭐ Single source of truth — read at session start
│   │   ├── journal.md                     # Append-only one-liner per session
│   │   └── next.md                        # Auto-generated kickoff prompt
│   ├── architecture/
│   │   ├── phase-plan.md                  # All phases + dependencies + outcomes
│   │   ├── decisions/                     # ADRs (immutable once accepted)
│   │   └── interfaces/                    # Module contracts, schemas (optional)
│   ├── phases/
│   │   └── phase-1-<name>/                # Per-phase scaffolding
│   │       ├── README.md                  # Goal, outcome, done criteria, rollback, deferred
│   │       └── steps.md                   # Checkbox checklist with [HALT] markers
│   ├── issues/
│   │   ├── OPEN/                          # Active major/blocker issues
│   │   └── RESOLVED/                      # Closed issues (regression test required)
│   ├── runbooks/                          # Full session protocols (kind=framework)
│   │   ├── session-start.md
│   │   ├── session-end.md
│   │   └── work-priority.md               # v2.0+ priority decision tree
│   ├── templates/                         # Blank starters (kind=framework)
│   │   ├── adr.md, adr-example.md
│   │   ├── issue.md, issue-example.md
│   │   ├── phase-readme.md, phase-steps.md
│   │   └── spec-artifact.md
│   ├── snapshots/                         # Hook-written; gitignored
│   │   ├── STATE-<ts>.md, journal-<ts>.md, next-<ts>.md   # PreCompact
│   │   ├── sessionend-{STATE,journal,next}-<ts>.md       # SessionEnd
│   │   ├── stop-<ts>.md                                  # Stop (per-turn)
│   │   └── markers.log                                   # Chronological event stream
│   └── .is-source-repo                    # Optional sentinel (gitignored); suppresses drift in Control's own dev repo
│
├── .claude/
│   ├── settings.json                      # Hook event wiring
│   ├── commands/                          # 10 slash commands (kind=framework)
│   │   ├── bootstrap.md, session-start.md, session-end.md, work-next.md
│   │   ├── phase-close.md, validate.md
│   │   ├── new-issue.md, close-issue.md
│   │   ├── new-adr.md
│   │   └── spec-amend.md
│   └── hooks/                             # Hook scripts in both runtimes (kind=framework)
│       ├── pre-compact-dump.{sh,ps1}
│       ├── session-start-load.{sh,ps1}
│       ├── session-end-commit.{sh,ps1}
│       ├── stop-snapshot.{sh,ps1}
│       ├── prune-snapshots.{sh,ps1}
│       └── regenerate-next-md.{sh,ps1}
│
├── .githooks/
│   └── commit-msg                         # Enforces commit-msg shape
│
├── CLAUDE.md                              # Auto-loaded by Claude Code every session
├── docs/                                  # UNTOUCHED by setup; project-owned long-form docs
└── (your code)
```

**`kind=framework`** files refresh on `UPGRADE=1`. **`kind=project`** files stay put.

---

## Validation & troubleshooting

Run `/validate` in Claude Code — checks STATE.md completeness, phase paths, ADR numbering, issue file shape, git tags, hook wiring. Reports issues without auto-fixing.

### Common issues

**Hook not firing.**

1. Check `.claude/settings.json` has all four event entries.
2. On Windows, confirm Git Bash is installed (`bash --version` works), OR `CONTROL_HOOK_RUNTIME=powershell` in `.control/config.sh`.
3. Run hooks manually to confirm they don't error:
   ```bash
   bash .claude/hooks/session-start-load.sh
   ```
4. Confirm Claude Code hook event names match (`PreCompact`, `SessionStart`, `SessionEnd`, `Stop`) against current Claude Code docs.

**Snapshots eating disk.**

Edit `.control/config.sh`:
```bash
CONTROL_SNAPSHOT_RETENTION_COUNT=20
CONTROL_SNAPSHOT_RETENTION_DAYS=7
```
Force a prune: `bash .claude/hooks/prune-snapshots.sh`.

**`/work-next` picking the wrong priority.**

STATE.md is stale. Run `/session-start`, compare reported status to reality, fix STATE.md by hand, commit.

**Session ended without `/session-end` (terminal just closed).**

The SessionEnd hook fires anyway and snapshots; check for a dirty-flag:

```bash
ls .control/snapshots/sessionend-dirty-*.flag
cat "$(ls -t .control/snapshots/sessionend-dirty-*.flag | head -1)"
```

```powershell
Get-ChildItem .control\snapshots\sessionend-dirty-*.flag
```

The flag describes uncommitted work at shutdown. Resume next session by reconciling.

**Drift on every session-start in Control's own dev repo.**

You're in the source repo and STATE.md is intentionally template-shaped. Create the source-repo sentinel:
```bash
touch .control/.is-source-repo
```

**`commit-msg` hook rejecting valid-looking commits.**

The shape is strict: `<type>(<phase>.<step>): <subject>` where `type` ∈ `CONTROL_COMMIT_TYPES` and the parens contents match the regex in `.githooks/commit-msg`. Bypass legitimately (only) with `git commit --no-verify`.

---

## Migration from v1.3

For upgrading an existing v1.3 install. If you're installing fresh, skip this section.

### Upgrade walkthrough

```bash
cd ~/projects/my-project
git tag pre-v2-migration                   # safety net for rollback
npx control-workflow upgrade
```

The installer will:

1. Refresh framework files (`.claude/commands/*.md`, `.claude/hooks/*.{sh,ps1}`, runbooks, templates, PROJECT_PROTOCOL.md)
2. Add `.control/.is-source-repo` and `.claude/settings.local.json` to `.gitignore` if not already present
3. **Prompt** (interactive only): "v1.3 spec layout detected. Migrate to v2.0 single-file layout? [y/N]"

If you say `n`, nothing changes — you can re-run later. If you say `y`:

- A new `.control/SPEC.md` is written, combining:
  - `## Overview` ← `.control/architecture/overview.md` content
  - `## Spec` ← `.control/spec/SPEC.md` content
  - `## Artifacts (chronological)` ← each `.control/spec/artifacts/*.md` as `### YYYY-MM-DD: <slug>` subsection
- The old files are MOVED (not copied) to `.control.v1.3-backup/`

Review the merged `.control/SPEC.md` (section headers note which old file each block came from), edit to taste, then commit:

```bash
git add .control/SPEC.md
git rm -rf .control.v1.3-backup    # or keep as backup, gitignored
git commit -m "chore: migrate spec layout to v2.0"
```

Verify the upgrade by running the SessionStart hook manually:

```bash
bash .claude/hooks/session-start-load.sh
```

You should see structured `[control:state]` / `[control:snapshot]` blocks (and `[control:drift]` / `[control:validate]` blocks if state mismatches reality). The trailing `-> Follow .claude/commands/session-start.md` line confirms v2.0 wiring is in place.

### Breaking changes

- **Spec layout collapsed.** v1.3 had `.control/spec/SPEC.md` + `.control/spec/artifacts/` + `.control/architecture/overview.md`. v2.0 has a single `.control/SPEC.md` with section structure. The interactive migration handles consolidation; old files backed up to `.control.v1.3-backup/`.
- **Hook output format changed.** Mixed prose+data heredoc → structured `[control:state]` / `[control:drift]` / `[control:validate]` blocks. Tooling that parsed the legacy `[DRIFT] ...` lines needs updating.
- **`/control-next`** removed in v2.1 (was deprecated alias in v2.0). Use `/session-start` (now idempotent — re-runnable mid-session).
- **`/new-spec-artifact`** removed in v2.1 (was deprecated alias in v2.0). Use `/spec-amend`.
- **PreCompact snapshots** use the `precompact-` filename prefix in v2.1 (was un-prefixed in v1.x and v2.0). The SessionStart hook accepts both prefixes via dual-glob lookup — old un-prefixed snapshots remain readable.

### Non-breaking additions

- "Control in 60 seconds" cover at top of README + PROJECT_PROTOCOL.md
- "Why these invariants" section (failure modes per rule)
- New helper hook: `regenerate-next-md.{sh,ps1}` (auto-generates next.md from STATE.md)
- Source-repo sentinel `.control/.is-source-repo` (forking Control? create this)
- Auto-validate at SessionStart (`[control:validate]` blocks for cheap fs-coherence checks)
- `commit-msg` hook now allows `redesign` type and `[A-Z](\.N[a-z]?)?` parens for redesign work
- New runbook `.control/runbooks/work-priority.md` (canonical priority logic shared by `/session-start` and `/work-next`)

### Manual migration (if not using setup)

If you can't run the installer interactively, do the migration by hand:

1. Create `.control/SPEC.md` with the new shape (use `.control/SPEC.md` from v2.0 source as a template)
2. Copy `.control/architecture/overview.md` content into the `## Overview` section
3. Copy `.control/spec/SPEC.md` content into the `## Spec` section (or merge into the canonical sections)
4. For each `.control/spec/artifacts/<date>-<slug>.md`, append a `### <date>: <slug>` subsection under `## Artifacts (chronological)`
5. Delete `.control/spec/` and `.control/architecture/overview.md` (or move to a backup dir)
6. Search-and-replace stale path refs in your `CLAUDE.md` and any project docs:
   - `.control/spec/SPEC.md` → `.control/SPEC.md`
   - `.control/spec/artifacts/` → "(SPEC.md `## Artifacts` section, populated by `/spec-amend`)"
   - `.control/architecture/overview.md` → "(SPEC.md `## Overview` section)"
7. Commit

### Rollback

The pre-v2-migration tag (set in step 1 of the walkthrough) is your rollback point:

```bash
git reset --hard pre-v2-migration
```

To revert ONLY the spec consolidation (keep other v2.0 changes), restore from the backup:

```bash
mv .control.v1.3-backup/spec .control/spec
mv .control.v1.3-backup/overview.md .control/architecture/overview.md
rm .control/SPEC.md
```

Then re-run `npx control-workflow upgrade` and decline the migration prompt.

---

## Platform notes

- **All platforms** — `npx control-workflow init` works the same on Linux, macOS, and Windows (PowerShell or Git Bash). Requires Node.js 18+ and Git.
- **Hook runtime auto-detected** — installer probes bash with `bash -c 'exit 0'`. If it works, hooks are wired as `bash .claude/hooks/<name>.sh`. Otherwise PowerShell hook ports are wired as `powershell -NoProfile -File ...`. PS hooks target PowerShell 5.1+ (bundled with Windows 7 SP1+, no install needed). Bash and PS hook output is byte-equivalent (verified by `tests/i5-parity.{sh,ps1}` in the source repo).
- **Switch runtime later** — edit `CONTROL_HOOK_RUNTIME=bash|powershell` in `.control/config.sh` and re-run `npx control-workflow upgrade`.
- **Claude Code** — hook event names (`PreCompact`, `SessionStart`, `SessionEnd`, `Stop`) are stable as of v1.0.0 of the framework. If Claude Code's hook API changes, update `.claude/settings.json` accordingly.

---

## Design philosophy

Three principles that shape every Control decision:

1. **Ship structure, not content.** Templates are skeletons; projects fill in richness. Filled examples (`adr-example.md`, `issue-example.md`) show *depth*, not *content*. Control gives you a frame, not the painting.

2. **Narrative before data, but data is enforced.** Operators see plain English; Claude reads structured data. Discipline (commit shape, drift detection, regression-test gate) is mechanical — never "ask Claude to verify Claude." The framework's anti-drift guarantee depends on this.

3. **Collapse the surface, not the discipline.** The user-facing surface should be small (~10 commands, one source-of-truth file). The enforcement layer can be rich (hooks, regex, gates). Discipline can be invisible to the operator and still operative.

**Three things that should never change:**

- Templates are starting skeletons, not boilerplate content.
- `docs/` is the project's namespace; Control touches only `.control/` and `.claude/`.
- STATE.md is a cursor; narrative history lives in commit messages and project-owned long-form docs.

---

## Roadmap

**v2.1** — released:

- Removed deprecated aliases: `/control-next`, `/new-spec-artifact`
- Snapshot pool naming consolidation (PreCompact files use `precompact-` prefix; old un-prefixed snapshots remain readable via dual-glob lookup)
- Documented `/clear` mid-session re-bootstrap (run `/session-start`)

**v2.2** — released:

- Shipped as `control-workflow` on npm; install via `npx control-workflow init`
- Replaced `setup.sh` / `setup.ps1` / `uninstall.sh` / `uninstall.ps1` with a single Node CLI (`tools/cli.js`); zero npm dependencies, pure Node built-ins
- Cross-platform install — same command on Linux, macOS, Windows PowerShell, Git Bash
- Hook runtime detection unchanged (bash if available, else PowerShell ports)

**v2.3+** (under consideration):

- Plugin model for new Claude Code hook events as the API evolves
- Multi-operator coordination (locks, conflict resolution on shared STATE.md)
- New autonomy stage (unattended mode with stricter gates)

---

## License

Use freely. No warranty. Fork and modify per project needs. If you ship a fork as your own framework, create the source-repo sentinel (`.control/.is-source-repo`) so Control's drift detection doesn't false-positive on your dev repo.

---

## Further reading

- **`.control/PROJECT_PROTOCOL.md`** — long-form framework reference (directory layout, file templates, slash commands deep-dive, session protocol, hooks, autonomy model, phase structure, issue flow, common pitfalls)
- **`archive/redesign-log.md`** — v2.0 design history (problem, principles, 22 resolved decisions, 8 implementation cycles)
- **`CLAUDE.md`** — what Claude Code auto-loads every session (project-specific invariants, key references)
- **`tests/README.md`** — test harness for the bash/PowerShell hook parity contract
