#!/usr/bin/env bash
# Control framework installer
#
# All Control-managed files land under .control/ (and .claude/). The project's
# docs/ at the root is NOT touched -- that namespace belongs to project content.
#
# Usage:
#   ./setup.sh [TARGET_DIR]
#   ./setup.sh                 # install into $PWD
#   ./setup.sh /path/to/proj   # install into /path/to/proj
#   FORCE=1 ./setup.sh ...     # overwrite existing project-managed files (use with care)
#   UPGRADE=1 ./setup.sh ...   # update framework files only; leave project content alone

set -euo pipefail

# --- paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR_RAW="${1:-$PWD}"

FORCE="${FORCE:-0}"
UPGRADE="${UPGRADE:-0}"

say() { printf "[control-setup] %s\n" "$*"; }
warn() { printf "[control-setup] WARNING: %s\n" "$*" >&2; }
die() { printf "[control-setup] ERROR: %s\n" "$*" >&2; exit 1; }

# --- checks (before any cd) ---
[ -d "$SCRIPT_DIR/.claude" ] || die "framework source not found at $SCRIPT_DIR -- run setup.sh from the control/ directory"
[ -d "$TARGET_DIR_RAW" ] || die "target directory does not exist: $TARGET_DIR_RAW"
command -v git >/dev/null || die "git is required. Install git and retry."
command -v bash >/dev/null || die "bash is required."

# Now safe to resolve absolute path
TARGET_DIR="$(cd "$TARGET_DIR_RAW" && pwd)"
CONTROL_VERSION="$(cat "$SCRIPT_DIR/VERSION")"

say "Installing Control v$CONTROL_VERSION into $TARGET_DIR"
[ "$UPGRADE" = "1" ] && say "(upgrade mode -- framework files only, project content untouched)"

cd "$TARGET_DIR"

# --- git init if missing ---
if [ ! -d .git ]; then
    say "Initialising git repository"
    git init --quiet
fi

# --- copy helper ---
# Copies src --> dst. Honours FORCE and UPGRADE modes.
#   kind=framework --> always overwritten in UPGRADE mode
#   kind=project   --> copied only if dst doesn't exist (unless FORCE=1)
copy_file() {
    local src="$1" dst="$2" kind="$3"
    local dst_dir
    dst_dir="$(dirname "$dst")"
    mkdir -p "$dst_dir"

    if [ ! -e "$dst" ]; then
        cp "$src" "$dst"
        say "  + $dst"
        return
    fi

    case "$kind" in
        framework)
            if [ "$UPGRADE" = "1" ] || [ "$FORCE" = "1" ]; then
                cp "$src" "$dst"
                say "  ~ $dst (updated)"
            else
                say "  = $dst (exists -- use UPGRADE=1 to update)"
            fi
            ;;
        project)
            if [ "$FORCE" = "1" ]; then
                cp "$src" "$dst"
                say "  ~ $dst (forced)"
            else
                say "  = $dst (exists -- kept; FORCE=1 to overwrite)"
            fi
            ;;
        *)
            die "copy_file: unknown kind '$kind'"
            ;;
    esac
}

# --- .control/ (framework-managed area; everything lives here except .claude/ and root files) ---
say "Installing .control/"
mkdir -p .control/snapshots
copy_file "$SCRIPT_DIR/.control/VERSION"   ".control/VERSION"   framework
copy_file "$SCRIPT_DIR/.control/config.sh" ".control/config.sh" project
[ -f .control/snapshots/.gitkeep ] || : > .control/snapshots/.gitkeep

# --- .claude/ ---
say "Installing .claude/settings.json, commands, hooks"
copy_file "$SCRIPT_DIR/.claude/settings.json" ".claude/settings.json" framework

for f in "$SCRIPT_DIR/.claude/commands/"*.md; do
    copy_file "$f" ".claude/commands/$(basename "$f")" framework
done

for f in "$SCRIPT_DIR/.claude/hooks/"*.sh; do
    [ -f "$f" ] || continue
    copy_file "$f" ".claude/hooks/$(basename "$f")" framework
    chmod +x ".claude/hooks/$(basename "$f")" 2>/dev/null || true
done

# Always-copy-both: PowerShell hook ports also installed (I5). The runtime
# wired in .claude/settings.json is decided at install time by setup.ps1's
# bash-detection block. Linux/macOS installs ship .ps1 files harmlessly.
for f in "$SCRIPT_DIR/.claude/hooks/"*.ps1; do
    [ -f "$f" ] || continue
    copy_file "$f" ".claude/hooks/$(basename "$f")" framework
done

# --- .githooks/ (git-side hooks; commit-msg shape enforcement) ---
if [ -d "$SCRIPT_DIR/.githooks" ]; then
    say "Installing .githooks/"
    for f in "$SCRIPT_DIR/.githooks/"*; do
        [ -f "$f" ] || continue
        copy_file "$f" ".githooks/$(basename "$f")" framework
        chmod +x ".githooks/$(basename "$f")" 2>/dev/null || true
    done
fi

# --- .control/ managed content ---
if [ "$UPGRADE" = "1" ]; then
    say "Upgrade mode: refreshing .control/templates/ and .control/runbooks/ only"
    for f in "$SCRIPT_DIR/.control/templates/"*.md; do
        copy_file "$f" ".control/templates/$(basename "$f")" framework
    done
    for f in "$SCRIPT_DIR/.control/runbooks/"*.md; do
        copy_file "$f" ".control/runbooks/$(basename "$f")" framework
    done
else
    say "Installing .control/ managed content"
    mkdir -p .control/{architecture/{decisions,interfaces},phases,progress,issues/{OPEN,RESOLVED},runbooks,templates}

    copy_file "$SCRIPT_DIR/.control/progress/STATE.md"              ".control/progress/STATE.md"              project
    copy_file "$SCRIPT_DIR/.control/progress/journal.md"            ".control/progress/journal.md"            project
    copy_file "$SCRIPT_DIR/.control/progress/next.md"               ".control/progress/next.md"               project
    copy_file "$SCRIPT_DIR/.control/architecture/phase-plan.md"     ".control/architecture/phase-plan.md"     project

    for f in "$SCRIPT_DIR/.control/runbooks/"*.md;  do copy_file "$f" ".control/runbooks/$(basename "$f")"  framework; done
    for f in "$SCRIPT_DIR/.control/templates/"*.md; do copy_file "$f" ".control/templates/$(basename "$f")" framework; done

    # v2.0: single SPEC.md at .control/ (was .control/spec/SPEC.md + spec/artifacts/ + architecture/overview.md)
    copy_file "$SCRIPT_DIR/.control/SPEC.md" ".control/SPEC.md" project

    [ -f .control/architecture/decisions/.gitkeep ] || : > .control/architecture/decisions/.gitkeep
    [ -f .control/issues/OPEN/.gitkeep ]            || : > .control/issues/OPEN/.gitkeep
    [ -f .control/issues/RESOLVED/.gitkeep ]        || : > .control/issues/RESOLVED/.gitkeep
    [ -f .control/phases/.gitkeep ]                 || : > .control/phases/.gitkeep
fi

# --- v1.3 -> v2.0 spec layout migration (UPGRADE only) ---
# Detects the old 3-location spec layout (.control/spec/SPEC.md + spec/artifacts/
# + architecture/overview.md) and offers to consolidate into the new single
# .control/SPEC.md. Skipped if already migrated (.control/SPEC.md exists),
# skipped on fresh installs (no .control/spec/), and skipped non-interactively.
# See MIGRATION-v1.3-to-v2.0.md for full details.
if [ "$UPGRADE" = "1" ] && [ ! -f .control/SPEC.md ] && { [ -d .control/spec ] || [ -f .control/architecture/overview.md ]; }; then
    if [ -t 0 ]; then
        say "v1.3 spec layout detected (.control/spec/ and/or .control/architecture/overview.md). Migrate to v2.0 single-file layout? [y/N]"
        read -r migrate_answer
        case "$migrate_answer" in
            y|Y|yes|YES)
                say "Migrating spec layout..."
                # Build the new SPEC.md with H2 sections preserving each old source
                {
                    echo "# Project Spec"
                    echo ""
                    echo "> Migrated from v1.3 layout on $(date -u +%Y-%m-%d). See MIGRATION-v1.3-to-v2.0.md."
                    echo ""
                    if [ -f .control/architecture/overview.md ]; then
                        echo "---"
                        echo ""
                        echo "## Overview (migrated from .control/architecture/overview.md)"
                        echo ""
                        cat .control/architecture/overview.md
                        echo ""
                    fi
                    if [ -f .control/spec/SPEC.md ]; then
                        echo "---"
                        echo ""
                        echo "## Spec (migrated from .control/spec/SPEC.md)"
                        echo ""
                        cat .control/spec/SPEC.md
                        echo ""
                    fi
                    if [ -d .control/spec/artifacts ]; then
                        echo "---"
                        echo ""
                        echo "## Artifacts (chronological, migrated from .control/spec/artifacts/)"
                        echo ""
                        for af in .control/spec/artifacts/*.md; do
                            [ -e "$af" ] || continue
                            echo "### $(basename "$af" .md)"
                            echo ""
                            cat "$af"
                            echo ""
                        done
                    fi
                } > .control/SPEC.md
                # Move old layout to backup so operator can verify the migration
                mkdir -p .control.v1.3-backup
                [ -d .control/spec ] && mv .control/spec .control.v1.3-backup/spec
                [ -f .control/architecture/overview.md ] && mv .control/architecture/overview.md .control.v1.3-backup/overview.md
                say "Migrated to .control/SPEC.md. Old files backed up to .control.v1.3-backup/."
                say "Review the merge, commit, then delete .control.v1.3-backup/ when satisfied."
                ;;
            *)
                say "Spec migration deferred. Run UPGRADE=1 again to retry, or migrate manually."
                ;;
        esac
    else
        warn "v1.3 spec layout detected but UPGRADE is non-interactive. Skipping migration."
        warn "Re-run setup.sh interactively, or migrate manually per MIGRATION-v1.3-to-v2.0.md."
    fi
fi

# --- CLAUDE.md, .control/PROJECT_PROTOCOL.md at root ---
copy_file "$SCRIPT_DIR/CLAUDE.md"             "CLAUDE.md"             project
if [ -f "$SCRIPT_DIR/.control/PROJECT_PROTOCOL.md" ]; then
    copy_file "$SCRIPT_DIR/.control/PROJECT_PROTOCOL.md" ".control/PROJECT_PROTOCOL.md" framework
fi

# --- .gitignore ---
GITIGNORE_MARKER="# --- Control framework ---"
if [ ! -f .gitignore ] || ! grep -qF "$GITIGNORE_MARKER" .gitignore; then
    say "Updating .gitignore"
    {
        echo ""
        echo "$GITIGNORE_MARKER"
        echo ".control/snapshots/"
        echo ".control/.is-source-repo"
        echo ".claude/settings.local.json"
        echo "# --- /Control ---"
    } >> .gitignore
fi

# --- Source-repo sentinel (v2.0+) ---
# Asks the operator (interactive only) whether this install is the Control
# source/dev repo. If yes, creates .control/.is-source-repo, which causes
# the SessionStart hook to skip all drift detection (because STATE.md ships
# as a starter template and is intentionally placeholder-shaped in the
# source repo). Skipped on UPGRADE and in non-interactive runs (CI, etc.).
if [ "$UPGRADE" != "1" ] && [ -t 0 ] && [ ! -f .control/.is-source-repo ]; then
    printf "Is this the Control source/dev repo (NOT a project using Control)? [y/N] "
    read -r is_source_answer
    case "$is_source_answer" in
        y|Y|yes|YES)
            cat > .control/.is-source-repo <<'SENTINEL'
# Control source/dev repo sentinel
# Created by setup.sh on operator confirmation.
# Suppresses SessionStart hook's drift detection so the shipped-as-template
# STATE.md doesn't trigger state-md-template drift every session.
CONTROL_SOURCE_REPO=true
SENTINEL
            say "Created .control/.is-source-repo (drift detection will skip on this repo)"
            ;;
    esac
fi

# --- initial commit + tag ---
if [ "$UPGRADE" = "1" ]; then
    say "Upgrade complete. Review changes with 'git status' and commit when ready."
else
    if git rev-parse HEAD >/dev/null 2>&1; then
        if ! git diff --quiet HEAD -- 2>/dev/null || [ -n "$(git status --porcelain)" ]; then
            git add -A
            git commit --quiet -m "chore(install): install Control framework v$CONTROL_VERSION"
            say "Committed: install Control framework v$CONTROL_VERSION"
        fi
    else
        git add -A
        git commit --quiet -m "chore(install): scaffold project with Control framework v$CONTROL_VERSION"
        say "Initial commit created"
    fi
    if ! git rev-parse protocol-initialised >/dev/null 2>&1; then
        git tag protocol-initialised
        say "Tagged: protocol-initialised"
    fi
fi

# --- Hook runtime default (I5) ---
# Setup.sh always defaults the hook runtime to bash on fresh install (Linux/macOS
# always have bash). setup.ps1 (Windows) detects bash availability and may write
# CONTROL_HOOK_RUNTIME=powershell instead.
if [ "$UPGRADE" != "1" ] && [ -f .control/config.sh ] && ! grep -q '^CONTROL_HOOK_RUNTIME=' .control/config.sh; then
    printf '\nCONTROL_HOOK_RUNTIME=bash\n' >> .control/config.sh
    say "Recorded CONTROL_HOOK_RUNTIME=bash in .control/config.sh"
fi

# --- wire core.hooksPath (skip if already set; preserves husky / pre-commit) ---
# Idempotent: safe to re-run. UPGRADE intentionally skipped to preserve operator state.
if [ "$UPGRADE" != "1" ] && [ -f .githooks/commit-msg ]; then
    EXISTING_HOOKS_PATH="$(git config --local --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$EXISTING_HOOKS_PATH" ]; then
        git config --local core.hooksPath .githooks
        say "Wired commit-msg hook (core.hooksPath = .githooks)"
    elif [ "$EXISTING_HOOKS_PATH" = ".githooks" ]; then
        say "core.hooksPath already set to .githooks -- commit-msg hook active"
    else
        warn "core.hooksPath is already set to '$EXISTING_HOOKS_PATH' (likely husky / pre-commit / lefthook)."
        warn "Control's commit-msg hook NOT auto-wired. To enable: chain '.githooks/commit-msg' from your existing hooksPath dir, OR unset and rerun setup."
    fi
fi

# --- nested-source cleanup hint ---
case "$SCRIPT_DIR" in
    "$TARGET_DIR"/*)
        if [ "$UPGRADE" != "1" ]; then
            echo ""
            say "Detected: the control/ source lives INSIDE this project."
            say "If you don't plan to re-install, remove it: rm -rf \"$SCRIPT_DIR\""
        fi
        ;;
esac

cat <<EOF

Control v$CONTROL_VERSION installed at $TARGET_DIR

Layout:
  CLAUDE.md                 -- auto-loaded every session
  .control/PROJECT_PROTOCOL.md       -- framework reference
  .control/                 -- all Control-managed files
    config.sh, VERSION, snapshots/
    progress/ architecture/ phases/ issues/ runbooks/ templates/ spec/
  .claude/                  -- commands, hooks, settings
  docs/                     -- UNTOUCHED (your project's own docs live here)

Next steps:
  1. If you have a spec file: /bootstrap <path-to-spec>
     If you don't: /bootstrap (no args -- scans the codebase and prompts you)
  2. Review the bootstrap output
  3. Commit
  4. /session-start

Run 'bash setup.sh' again with UPGRADE=1 to update framework files without touching your project content.

EOF
