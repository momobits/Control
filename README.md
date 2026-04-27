# Control — a phased session protocol for Claude Code

Control is a portable framework for running multi-phase, multi-session Claude Code projects without context rot or session drift. It installs slash commands, hooks, doc scaffolding, and a protocol reference into any project.

**Version:** see `VERSION`

> **NPM in the future:** the long-term distribution target is `npx control init`. Until Control is published, the flow below mimics that: copy `control/` into your project, run the installer, optionally delete `control/` afterwards. Works on Linux, macOS, and Windows.

---

## Table of contents

1. [What it gives you](#what-it-gives-you)
2. [Prerequisites](#prerequisites)
3. [The flow — copy, install, use](#the-flow--copy-install-use)
4. [Install walkthroughs](#install-walkthroughs) — A. Linux/macOS · B. Windows (Git Bash) · C. Windows (native PowerShell) · D. existing git repo · E. upgrade · F. uninstall
5. [Daily workflows](#daily-workflows) — G. first session · H. single step · I. autonomous loop · J. minor bug · K. major bug · L. new ADR · M. close phase · N. session handoff
6. [Recovery](#recovery) — O. compaction · P. botched STATE · Q. rollback phase
7. [Validation & troubleshooting](#validation--troubleshooting)
8. [Reference](#reference)
9. [Platform notes](#platform-notes)

---

## What it gives you

- **`/work-next`** — autonomous prioritiser. Claude picks and executes the next item without being told.
- **`/loop /work-next`** — autonomous loop within a session.
- **`PreCompact` + `SessionStart` + `SessionEnd` + `Stop` hooks** — state persists automatically.
- **Phase/step/issue/ADR scaffolding** — institutional memory that survives context collapse.
- **Git-integrated** — commits per step, tags per phase, rollback via `git reset --hard phase-N-closed`.
- **`commit-msg` hook** — git-side enforcement of the `<type>(<phase>.<step>): <subject>` shape; rejects malformed commits at commit time so `git log` stays a faithful phase narrative.
- **Severity-gated issues** — minor bugs get a journal line; only major/blocker get files + regression tests.

---

## Prerequisites

| Need | Why |
|---|---|
| **git** | Every phase step commits; every phase close tags. Non-optional. |
| **bash** *(for Claude Code hooks)* | Hook scripts are POSIX bash. On Windows this means **Git Bash** (installed automatically with Git for Windows) or **WSL**. |
| **PowerShell 5+** *(optional, Windows only)* | If you want to run install/uninstall without Git Bash. The hooks still need bash, but the install itself works in pure PowerShell. |
| **Claude Code** CLI | Obviously. |

You do **not** need: Python, Node, yq, jq, or any other runtime.

---

## The flow — copy, install, use

The process mimics `npx control init` until Control is actually on npm:

```
1. Copy control/ into your project          (drag-and-drop, git clone, unzip — any way)
2. Run the installer from inside the project (bash or PowerShell — see below)
3. Optionally delete control/ afterwards     (installer hints at this)
4. Use /session-start and go                 (framework is now active)
```

After install, your project has `.control/` (all framework-managed files), `.claude/` (commands + hooks), `CLAUDE.md`, and `.control/PROJECT_PROTOCOL.md`. Your project's `docs/` at the root is **not touched** — that namespace is yours for project-owned docs. The framework **source** (`control/`) is separate from what gets **installed** (`.control/`) — different things despite similar names.

---

## Install walkthroughs

### A. Linux / macOS

```bash
# 1. Copy control/ into your project (one of these works)
cp -r /path/to/control ~/projects/my-project/
# or
cd ~/projects/my-project && git clone <your-control-repo> control
# or
cd ~/projects/my-project && curl -L <url-to-control.tar.gz> | tar xz

# 2. Install from inside the project
cd ~/projects/my-project
bash control/setup.sh

# 3. Optional cleanup — installer reminded you
rm -rf control

# Result:
#   ~/projects/my-project/
#   ├── CLAUDE.md, PROJECT_PROTOCOL.md
#   ├── .control/       <- Control-managed: progress, phases, issues, spec, etc.
#   ├── .claude/        <- Control-managed: commands + hooks
#   ├── .git/           <- initialized if it wasn't
#   ├── docs/           <- UNTOUCHED: your project's own docs live here
#   └── (your code if any)
# The control/ source is gone; the installed framework is in place.
```

### B. Windows (Git Bash) — recommended

Identical to Linux/macOS, using Git Bash. This is the recommended Windows path since Claude Code hooks need bash anyway.

```bash
# In Git Bash
cd /c/Users/Momo/projects/my-project

# Copy control/ in (however — File Explorer, unzip, git clone, etc.)
# Assume you've dropped control/ into the project already.

# Install
bash control/setup.sh

# Optional cleanup
rm -rf control
```

### C. Windows (native PowerShell — no Git Bash)

Use this if you don't have Git Bash and don't want to install it. The install works natively, but **Claude Code hooks will not run** without bash on the system — the protocol still works manually, just without the auto-state-persistence layer.

```powershell
# In PowerShell
cd C:\Users\Momo\projects\my-project

# Copy control/ in (Explorer, Copy-Item, git clone, etc.)

# Install
.\control\setup.ps1

# If execution policy blocks it:
powershell -ExecutionPolicy Bypass -File .\control\setup.ps1

# Optional cleanup
Remove-Item -Recurse -Force .\control
```

> **Strongly recommended on Windows:** install [Git for Windows](https://git-scm.com/) (free, includes Git Bash). The hook layer — which is the core anti-drift automation — needs bash. You can use PowerShell for the install itself but hooks won't fire without bash.

### D. Installing into an existing git repo

Same flow as above. The installer detects existing `.git/` and skips `git init`. Your existing history and branches are preserved. The installer commits the framework addition with:

```
chore: install Control framework v1.0.0
```

Then adds the `protocol-initialised` tag.

If your working tree is dirty when you install, the installer will include those changes in the install commit. To avoid this, stash or commit first:

```bash
git status        # check for uncommitted changes
git stash         # or: git commit them first
bash control/setup.sh
git stash pop     # restore after install
```

### E. Upgrade an existing Control install

When `control/` has been updated and you want to refresh the framework in an installed project:

```bash
# Linux / macOS / Git Bash
cd ~/projects/my-project
cp -r /path/to/updated-control ./control   # or git pull if control/ is a repo
UPGRADE=1 bash control/setup.sh
git diff                                    # review
git commit -am "chore: upgrade Control to v1.0.1"
rm -rf control                              # or keep for next time
```

```powershell
# Windows PowerShell
cd C:\Users\Momo\projects\my-project
Copy-Item -Recurse -Force C:\tools\updated-control .\control
.\control\setup.ps1 -Upgrade
git diff
git commit -am "chore: upgrade Control to v1.0.1"
Remove-Item -Recurse -Force .\control
```

Upgrade mode refreshes: `.control/VERSION`, `.claude/settings.json`, `.claude/commands/*.md`, `.claude/hooks/*.sh`, `.control/runbooks/*.md`, `.control/templates/*.md`, `.control/PROJECT_PROTOCOL.md`.

Upgrade mode does **not** touch: `.control/config.sh`, `CLAUDE.md`, `.control/progress/*`, `.control/architecture/overview.md`, `.control/architecture/phase-plan.md`, `.control/phases/*`, `.control/issues/*`, `.control/architecture/decisions/*`.

### F. Uninstall

```bash
# Linux / macOS / Git Bash
bash control/uninstall.sh          # if control/ still in project
# or
bash /path/to/control/uninstall.sh /path/to/project

# Windows PowerShell
.\control\uninstall.ps1
# or
C:\tools\control\uninstall.ps1 -TargetDir C:\path\to\project

# Skip the prompt
FORCE=1 bash control/uninstall.sh
.\control\uninstall.ps1 -Force
```

Uninstaller removes: `.control/`, `.claude/settings.json`, the 5 hook scripts, the 8 command files, `.control/PROJECT_PROTOCOL.md`, `CLAUDE.md` (only if it still has the `<!-- control:managed -->` marker), and the Control block from `.gitignore`.

Uninstaller leaves: `docs/` (your project docs), all git history and tags, all code.

---

## Daily workflows

### G. First session after install

You have two paths. If you have a spec/PRD/design doc at the project root, use the fast path; otherwise fill the templates manually.

#### G1. Fast path -- `/bootstrap` from a spec (recommended when you have one)

Drop your spec file at the project root (any name, `.md` recommended), then in Claude Code:

```
/bootstrap <spec-filename>.md
```

Claude reads the spec, confirms the project name + proposed phase list with you, then populates:

- `CLAUDE.md` -- with project-specific invariants extracted from the spec
- `.control/architecture/overview.md` -- distilled architecture reference
- `.control/architecture/phase-plan.md` -- full phase list with dependencies + outcomes
- `.control/phases/phase-1-<name>/README.md` + `steps.md` -- Phase 1 scaffold
- `.control/progress/STATE.md` -- set to Phase 1, step 1.1

Review the draft. Commit. Run `/session-start`. Ready to work.

#### G2. Manual path -- fill the templates yourself

If there's no spec, or you prefer to write it yourself:

1. **`CLAUDE.md`** -- replace `<PROJECT_NAME>`; add project-specific invariants under `## Invariants`.
2. **`.control/architecture/overview.md`** -- problem statement, scope, tech choices.
3. **`.control/architecture/phase-plan.md`** -- enumerate phases (name, dependencies, outcomes).
4. **Scaffold Phase 1:**

   Linux/macOS/Git Bash:
   ```bash
   mkdir -p .control/phases/phase-1-<your-phase-name>
   cp .control/templates/phase-readme.md .control/phases/phase-1-<your-phase-name>/README.md
   cp .control/templates/phase-steps.md  .control/phases/phase-1-<your-phase-name>/steps.md
   ```

   Windows PowerShell:
   ```powershell
   New-Item -ItemType Directory docs\phases\phase-1-<your-phase-name>
   Copy-Item docs\templates\phase-readme.md docs\phases\phase-1-<your-phase-name>\README.md
   Copy-Item docs\templates\phase-steps.md  docs\phases\phase-1-<your-phase-name>\steps.md
   ```

5. Edit both new files with the phase's goal, steps, and done criteria.
6. Update `.control/progress/STATE.md`:
   - Set `Current phase` to `1 -- <your-phase-name>`
   - Set `Current step` to `1.1`
   - Set `Next action` to match step 1.1

7. Commit:
   ```bash
   git add -A
   git commit -m "chore: bootstrap project docs and Phase 1"
   ```

8. Open Claude Code in the project directory and type `/session-start`.

> **Why `/bootstrap` is the better path:** it uses Claude's judgment to extract non-obvious invariants, phase ordering, and sub-step detail from a dense spec -- work a human would spend 1-2 hours doing by hand. You still review the output; you don't write it from scratch.

### H. Running a single step (Stage 1 — semi-auto)

```
You:    /session-start
Claude: [reports status, waits]
You:    go
Claude: [implements step, commits, updates state]
You:    /session-end
Claude: [closes session, writes next.md, prints kickoff prompt]
```

### I. Running autonomously (Stage 2 — step-loop)

```
You:    /loop /work-next
Claude: [iterates: pick → implement → commit → update STATE → pick next]
        [halts on any HALT condition]

HALT example:
Claude: [HALT] New ADR needed — chat-agent framework choice
        Current step: 3.2
        What's needed from you: decide between DSPy ReAct and LangGraph
        STATE.md updated. Resume with /work-next when ready.

You:    /new-adr chat-agent-framework
         [walk through ADR]
You:    /loop /work-next     (resume)
```

Iteration budget default is 20; change in `.control/config.sh`.

### J. Fixing a minor bug

```
You:    /new-issue error-typo
Claude: Symptom?
You:    error message says "allow" instead of "allowed"
Claude: Severity?
You:    minor
Claude: [fixes inline, commits, adds journal line, NO file created]
```

### K. Fixing a major/blocker bug

```
You:    /new-issue theme-discovery-flakiness
Claude: Symptom?
You:    theme-discovery test fails ~20% of the time
Claude: Severity?
You:    major
Claude: [creates .control/issues/OPEN/<date>-theme-discovery-flakiness.md, commits, journal entry]

You:    go
Claude: [investigates, writes hypothesis, implements fix, writes regression test]
        Ready to close?
You:    yes
You:    /close-issue <date>-theme-discovery-flakiness
Claude: [verifies regression test exists, moves file to RESOLVED/, commits, journal]
```

`/close-issue` refuses to close without a regression test. Don't work around this.

### L. Making an architectural decision

```
You:    /new-adr embedding-model-for-chat-recall
Claude: [walks you through Context / Decision / Alternatives / Consequences]
        [creates .control/architecture/decisions/0003-embedding-model-for-chat-recall.md as proposed]
You:    Accept it.
Claude: [changes status to accepted, commits, updates STATE.md Recent decisions]
```

### M. Closing a phase

```
You:    /phase-close
Claude: Checking done criteria for Phase 2:
        ✓ All steps checked off
        ✓ No phase:2-blocker issues open
        ✓ Tests pass (47/0)
        ✓ Eval score 0.84 ≥ baseline 0.80
        ✗ Smoke test: needs manual verification

You:    [run the smoke test manually]
        smoke test passed
Claude: /phase-close [re-run]
        [all green — creates tag phase-2-analyst-closed]
        [scaffolds phase-3 dir, updates STATE, commits, prints next session prompt]
```

### N. Session handoff

```
# End of day
You:    /session-end
Claude: [commits dirty work, updates STATE, writes next.md, prints kickoff prompt]

# Next day — fresh Claude Code session in the same project
# Option 1: SessionStart hook auto-bootstraps (if bash is installed)
# Option 2: paste the prompt from .control/progress/next.md

You:    [paste prompt from .control/progress/next.md]
Claude: [bootstraps, reports status, waits for go]
```

---

## Recovery

### O. Recovering from a compaction event

The `PreCompact` hook auto-snapshots to `.control/snapshots/` before compaction runs.

```bash
# Linux / macOS / Git Bash
ls -la .control/snapshots/                              # list snapshots
diff .control/progress/STATE.md .control/snapshots/STATE-<ts>.md    # compare
cp .control/snapshots/STATE-<ts>.md .control/progress/STATE.md      # restore if needed
```

```powershell
# Windows PowerShell
Get-ChildItem .control\snapshots\
Compare-Object (Get-Content docs\progress\STATE.md) (Get-Content .control\snapshots\STATE-<ts>.md)
Copy-Item .control\snapshots\STATE-<ts>.md docs\progress\STATE.md -Force
```

### P. Botched STATE.md

```bash
# Option 1: roll back to last git commit
git checkout HEAD -- .control/progress/STATE.md

# Option 2: most recent snapshot (bash)
cp "$(ls -t .control/snapshots/STATE-*.md | head -1)" .control/progress/STATE.md

# PowerShell equivalent
Copy-Item (Get-ChildItem .control\snapshots\STATE-*.md | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName docs\progress\STATE.md -Force
```

### Q. Rolling back a phase

```bash
# Reset to the tag of the previous closed phase
git reset --hard phase-2-analyst-closed
```

Same command on Windows; git behaves identically.

---

## Validation & troubleshooting

Run `/validate` in Claude Code — it checks STATE.md completeness, phase paths, ADR numbering, issue files, git tags, hook wiring.

**Hook not firing?**
1. Check `.claude/settings.json` has the four event entries.
2. On Windows: confirm Git Bash is installed — `bash --version` should work in cmd/PowerShell or via the Git Bash terminal.
3. Run hooks manually to confirm they don't error:
   ```bash
   bash .claude/hooks/session-start-load.sh
   ```
4. Confirm Claude Code hook event names match (`PreCompact`, `SessionStart`, `SessionEnd`, `Stop`) — verify against current Claude Code docs.

**Snapshots eating disk?**
Edit `.control/config.sh`:
```bash
CONTROL_SNAPSHOT_RETENTION_COUNT=20
CONTROL_SNAPSHOT_RETENTION_DAYS=7
```
Force a prune: `bash .claude/hooks/prune-snapshots.sh`.

**`/work-next` picking wrong priority?**
STATE.md is stale. Run `/session-start`, compare reported status to reality, fix STATE.md by hand.

**Session ended without `/session-end` (terminal just closed)?**
Check for shutdown-dirty flags:
```bash
ls .control/snapshots/sessionend-dirty-*.flag
cat "$(ls -t .control/snapshots/sessionend-dirty-*.flag | head -1)"
```
```powershell
Get-ChildItem .control\snapshots\sessionend-dirty-*.flag
```

---

## Reference

### Commands

| Command | Purpose |
|---|---|
| `/bootstrap <spec-file>` | One-shot derivation: reads a spec/PRD and populates CLAUDE invariants, overview, phase-plan, Phase 1 scaffold, STATE |
| `/session-start` | Bootstrap the session; report status |
| `/session-end` | Close the session; update STATE, journal, next.md; commit |
| `/work-next` | Pick and execute the next item per priority rules |
| `/loop /work-next` | Autonomous loop |
| `/new-issue <slug>` | Open an issue (severity-gated) |
| `/close-issue <id>` | Close major/blocker issue (needs regression test) |
| `/new-adr <slug>` | New Architecture Decision Record |
| `/phase-close` | Verify done criteria, tag, scaffold next phase |
| `/validate` | Sanity-check protocol files |

### Install flags

| Bash | PowerShell | Purpose |
|---|---|---|
| `FORCE=1 bash setup.sh` | `.\setup.ps1 -Force` | Overwrite existing project-managed files |
| `UPGRADE=1 bash setup.sh` | `.\setup.ps1 -Upgrade` | Framework files only; leave project content |
| `FORCE=1 bash uninstall.sh` | `.\uninstall.ps1 -Force` | Skip confirmation prompt |

### Config (`.control/config.sh`)

| Variable | Default | Purpose |
|---|---|---|
| `CONTROL_MAX_AUTO_ITERATIONS` | `20` | Hard cap on `/loop /work-next` |
| `CONTROL_HALT_CONDITIONS` | 8 items | Conditions that stop the loop |
| `CONTROL_COMMIT_FORMAT` | `{type}({phase}.{step}): {subject}` | Commit shape |
| `CONTROL_COMMIT_TYPES` | `feat fix test docs refactor chore` | Allowed types |
| `CONTROL_PHASE_CLOSE_TAG_FORMAT` | `phase-{n}-{name}-closed` | Tag shape |
| `CONTROL_ISSUE_FILE_REQUIRED_FOR` | `blocker major` | Severities needing a file |
| `CONTROL_ISSUE_JOURNAL_ONLY` | `minor` | Severities getting only a journal line |
| `CONTROL_SNAPSHOT_RETENTION_COUNT` | `50` | Max snapshots kept |
| `CONTROL_SNAPSHOT_RETENTION_DAYS` | `14` | Snapshot age cap |

### Tags

| Tag | Set by | Meaning |
|---|---|---|
| `protocol-initialised` | `setup.sh` / `setup.ps1` | Control installed + committed |
| `phase-<N>-<name>-closed` | `/phase-close` | Phase verified and shipped |

---

## Platform notes

- **Linux / macOS:** `setup.sh` works with any recent bash. All hooks work out of the box.
- **Windows (Git Bash):** recommended path. Install [Git for Windows](https://git-scm.com/) — bundles bash and all POSIX tools the hooks need. `setup.sh` runs in Git Bash identically to Linux.
- **Windows (PowerShell, no Git Bash):** `setup.ps1` and `uninstall.ps1` let you install and remove natively. The hook layer will not function without bash on the PATH — the framework degrades gracefully (manual `/session-start` / `/session-end` still work; only auto-bootstrap and auto-state-snapshot are disabled).
- **Claude Code:** hook event names (`PreCompact`, `SessionStart`, `SessionEnd`, `Stop`) are stable as of v1.0.0. If the Claude Code API changes, update `.claude/settings.json` accordingly.

---

## Towards NPM

Once Control is ready for npm publishing, the flow becomes:

```bash
npx control init [target-dir]          # replaces: copy + bash setup.sh
npx control upgrade                    # replaces: UPGRADE=1 bash setup.sh
npx control uninstall                  # replaces: bash uninstall.sh
```

Until then, the copy-into-project flow above is the stable interface.

---

## License

Use freely. No warranty. Fork and modify per project needs.
