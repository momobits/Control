# Migrating from Control v1.3 to v2.0

> Practical upgrade guide. Most changes are automatic via `UPGRADE=1`; the only operator-facing migration is the spec layout consolidation, which prompts before touching anything.

**Version target:** v1.3.x → v2.0.0
**Migration risk:** low — the only destructive step (spec layout consolidation) prompts before running and backs up old files to `.control.v1.3-backup/`.
**Time required:** ~5 minutes for fresh upgrade; ~15 minutes if you have customized spec layout.

---

## What changed in v2.0

Five operator-visible changes:

1. **Lead-with-essence docs** (Group A). README and PROJECT_PROTOCOL now open with a "Control in 60 seconds" cover section: problem framing, single architecture diagram, three storage layers, five enforced invariants. Existing reference content moved later. No file deletions.

2. **Narrative output** (Group B). Slash commands (`/session-start`, `/work-next`, `/phase-close`, `/validate`) default to 2-4 sentence plain-English status. Verbose structured block on `--verbose`, on operator request ("show me the status block"), or auto-shown when drift / blockers / errors demand attention.

3. **Hook output is structured data** (Group B). The SessionStart hook now emits `[control:state]` / `[control:snapshot]` / `[control:drift]` blocks instead of mixed prose+data heredoc. Claude reads the blocks and narrates to operators. Drift formats: `state-md-{missing,template,unparseable}` and `{branch,commit,uncommitted,tag}-mismatch` (with `expected:`/`actual:` fields).

4. **Spec layout collapsed** (Group C, biggest visible change). The three v1.3 spec locations (`.control/spec/SPEC.md` + `.control/spec/artifacts/` + `.control/architecture/overview.md`) are folded into a single `.control/SPEC.md`. The `/spec-amend <slug>` command appends a dated section to its `## Artifacts (chronological)` heading. `/new-spec-artifact` becomes a deprecated alias for one minor version.

5. **Source-repo sentinel** (Group C). New `.control/.is-source-repo` file (gitignored) suppresses the SessionStart hook's drift detection. Only relevant if you forked Control as a starting point — operators of derivative projects don't need this.

---

## Upgrade walkthrough

### Step 1: Run the installer

From inside your project directory (with the updated `control/` source available):

```bash
# Linux / macOS / Git Bash
UPGRADE=1 bash control/setup.sh
```

```powershell
# Windows native PowerShell
.\control\setup.ps1 -Upgrade
```

Setup will:
- Refresh framework files (`.claude/commands/*.md`, `.claude/hooks/*.{sh,ps1}`, `.control/runbooks/*.md`, `.control/templates/*.md`, `.control/PROJECT_PROTOCOL.md`)
- Add `.control/.is-source-repo` and `.claude/settings.local.json` to `.gitignore` if not already present
- **Prompt** (interactive only): "v1.3 spec layout detected. Migrate to v2.0 single-file layout? [y/N]"

If you say `n`, nothing changes — you can re-run later. If you say `y`, see **Step 2**.

If you run setup non-interactively (CI, etc.), the spec migration is skipped with a warning and you'll need to re-run interactively or migrate manually (see **Manual migration** below).

### Step 2 (optional): Confirm spec migration

If you answered `y` to the migration prompt:

- A new `.control/SPEC.md` is written, combining:
  - `## Overview` section ← `.control/architecture/overview.md` content
  - `## Spec` section ← `.control/spec/SPEC.md` content
  - `## Artifacts (chronological)` section ← each `.control/spec/artifacts/*.md` as a `### YYYY-MM-DD: <slug>` subsection
- The old files are MOVED (not copied) to `.control.v1.3-backup/`:
  - `.control.v1.3-backup/spec/` (the old spec dir)
  - `.control.v1.3-backup/overview.md` (the old overview)

**Review the merged file** — `.control/SPEC.md`. Section headers tell you which old file each block came from. Edit the consolidated form to your taste (de-duplicate, reorder, retitle sections).

When satisfied:

```bash
git add .control/SPEC.md
git rm -rf .control.v1.3-backup    # or keep as a backup, gitignored
git commit -m "chore: migrate spec layout to v2.0"
```

### Step 3: Verify the upgrade

Run the SessionStart hook manually once to confirm output:

```bash
bash .claude/hooks/session-start-load.sh
```

You should see:

```
[control:SessionStart]

[control:state]
branch: <yours>
last-commit-sha: <yours>
last-commit-subject: <yours>
working-tree: clean | dirty
last-tag: <yours>
[/control:state]

[control:snapshot]
latest-precompact: <path-or-none>
[/control:snapshot]

[control:drift]   # only if STATE.md drifted from git
type: <type>
... (per-type fields)
[/control:drift]

-> Follow .claude/commands/session-start.md to bootstrap. ...
```

If the output looks structured and the trailing `-> Follow...` line is present, the v2.0 hook is installed correctly.

---

## Manual migration (if not using setup)

If you can't run the installer interactively, do the migration by hand:

1. Create `.control/SPEC.md` with the new shape (use `.control/SPEC.md` from the v2.0 source repo as a template).
2. Copy the content of your existing `.control/architecture/overview.md` into the `## Overview` section.
3. Copy the content of your existing `.control/spec/SPEC.md` into the `## Spec` section (or merge into the canonical sections — Overview, Problem statement, Scope, Tech choices, etc.).
4. For each `.control/spec/artifacts/<date>-<slug>.md`, append a `### <date>: <slug>` subsection under `## Artifacts (chronological)` containing the artifact's content (drop the H1; use H4 for sub-sections).
5. Delete `.control/spec/` and `.control/architecture/overview.md` (or move them to a backup dir).
6. Verify `.control/SPEC.md` is coherent.
7. Commit.

---

## Updating CLAUDE.md, STATE.md, and other docs

After the spec consolidation, your project's own `CLAUDE.md` and STATE.md may still reference the old paths. Search and replace:

- `.control/spec/SPEC.md` → `.control/SPEC.md`
- `.control/spec/artifacts/` → "(SPEC.md `## Artifacts` section, populated by `/spec-amend`)"
- `.control/architecture/overview.md` → "(SPEC.md `## Overview` section)"

If you have any in-repo docs that reference these paths in narrative (e.g. "see overview.md for the architecture diagram"), update them to point at `.control/SPEC.md` Overview section.

---

## Backward-compat notes

- **`/control-next`** is kept as a deprecated alias for v2.0; removal scheduled for v2.1. Its priority logic moves into `/session-start` (idempotent — re-runnable mid-session).
- **`/new-spec-artifact`** is kept as a deprecated alias for v2.0; removal scheduled for v2.1. It now invokes `/spec-amend` semantically.
- **Hook output format change** is breaking for any tooling that parsed the old `[DRIFT] ...` prose lines. If you have such tooling, update it to parse `[control:drift]` blocks. Standard operators just see Claude's narration and don't notice.
- **Snapshot pool unification** (D10) is scheduled for cycle 5e — a single retention pool with `<type>-<timestamp>.md` naming. Existing snapshots are not migrated; they'll prune naturally as they age out.

---

## Rollback

The installer does not auto-tag a pre-migration state. Before running `UPGRADE=1`, take a snapshot:

```bash
git tag pre-v2-migration
```

To revert:

```bash
git reset --hard pre-v2-migration
# (re-apply any commits made after the migration but unrelated to it, manually)
```

If you only want to revert the spec consolidation (the only destructive change), recover from `.control.v1.3-backup/`:

```bash
mv .control.v1.3-backup/spec .control/spec
mv .control.v1.3-backup/overview.md .control/architecture/overview.md
rm .control/SPEC.md
```

Then re-run `UPGRADE=1` declining the migration prompt.

---

## What's next (after v2.0.0)

v2.1 (planned):
- Remove `/control-next` and `/new-spec-artifact` deprecated aliases
- `/control-next` priority logic absorbed into `/session-start` via `.control/runbooks/work-priority.md`
- Snapshot pool unification (D10): single retention pool with type-prefixed filenames

v2.2+:
- `/clear` mid-session handling (deferred per D21)
- Plugin model for new Claude Code hook events
- Multi-operator coordination (deferred per D2)

See `redesign-log.md` (project root) for the full design history of v2.0.
