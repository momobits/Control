#!/usr/bin/env bash
# Control framework uninstaller
#
# Removes the entire .control/ directory, Control-managed files in .claude/,
# and root-level framework files (CLAUDE.md only if it bears the marker).
# Leaves docs/ (project-owned), git history, tags, and application code intact.
#
# Usage:
#   ./uninstall.sh [TARGET_DIR]
#   FORCE=1 ./uninstall.sh ...   to skip the confirmation prompt

set -euo pipefail

TARGET_DIR_RAW="${1:-$PWD}"
FORCE="${FORCE:-0}"

say() { printf "[control-uninstall] %s\n" "$*"; }
die() { printf "[control-uninstall] ERROR: %s\n" "$*" >&2; exit 1; }

[ -d "$TARGET_DIR_RAW" ] || die "target directory does not exist: $TARGET_DIR_RAW"
TARGET_DIR="$(cd "$TARGET_DIR_RAW" && pwd)"

[ -d "$TARGET_DIR/.control" ] || { say "No Control install detected at $TARGET_DIR"; exit 0; }

cat <<EOF
This will remove the Control framework from:
  $TARGET_DIR

Will remove:
  - .control/                  (entire directory: progress, phases, issues, spec, etc.)
  - .claude/settings.json and Control-managed command / hook files
  - CLAUDE.md  (only if it carries the <!-- control:managed --> marker)
  - PROJECT_PROTOCOL.md
  - Control block from .gitignore

Will NOT touch:
  - docs/                       (project-owned docs stay intact)
  - Git history, tags, or any commits
  - Your code or application files

EOF

if [ "$FORCE" != "1" ]; then
    read -rp "Proceed? [y/N] " ans
    case "${ans:-n}" in
        y|Y|yes|YES|Yes) ;;
        *) say "Aborted."; exit 1 ;;
    esac
fi

cd "$TARGET_DIR"

# .control/ goes in one shot now that everything is nested inside it
rm -rf .control

# .claude/ -- remove only Control-managed files
rm -f .claude/settings.json
rm -f .claude/hooks/pre-compact-dump.sh
rm -f .claude/hooks/session-start-load.sh
rm -f .claude/hooks/session-end-commit.sh
rm -f .claude/hooks/stop-snapshot.sh
rm -f .claude/hooks/prune-snapshots.sh
# PowerShell hook ports (I5)
rm -f .claude/hooks/pre-compact-dump.ps1
rm -f .claude/hooks/session-start-load.ps1
rm -f .claude/hooks/session-end-commit.ps1
rm -f .claude/hooks/stop-snapshot.ps1
rm -f .claude/hooks/prune-snapshots.ps1
rm -f .claude/commands/bootstrap.md
rm -f .claude/commands/control-next.md       # legacy alias (removed v2.1; clean up old installs)
rm -f .claude/commands/session-start.md
rm -f .claude/commands/session-end.md
rm -f .claude/commands/work-next.md
rm -f .claude/commands/new-issue.md
rm -f .claude/commands/close-issue.md
rm -f .claude/commands/new-adr.md
rm -f .claude/commands/new-spec-artifact.md  # legacy alias (removed v2.1; clean up old installs)
rm -f .claude/commands/spec-amend.md
rm -f .claude/commands/phase-close.md
rm -f .claude/commands/validate.md

# Remove now-empty .claude/ subdirs
rmdir .claude/commands 2>/dev/null || true
rmdir .claude/hooks 2>/dev/null || true
rmdir .claude 2>/dev/null || true

# --- .githooks/ -- remove Control's commit-msg only (preserve user-added hooks) ---
if [ -f .githooks/commit-msg ] && grep -q "control:commit-msg" .githooks/commit-msg 2>/dev/null; then
    rm -f .githooks/commit-msg
    rmdir .githooks 2>/dev/null || true
fi

# --- core.hooksPath -- revert only if Control set it ---
HOOKS_PATH="$(git config --local --get core.hooksPath 2>/dev/null || true)"
if [ "$HOOKS_PATH" = ".githooks" ]; then
    git config --local --unset core.hooksPath
    say "Unset core.hooksPath (was .githooks -- set by Control)"
fi

# Root-level framework files
rm -f PROJECT_PROTOCOL.md

# Only remove CLAUDE.md if it still bears the explicit Control marker.
if [ -f CLAUDE.md ] && grep -q "<!-- control:managed -->" CLAUDE.md; then
    rm -f CLAUDE.md
    say "Removed CLAUDE.md (bore the <!-- control:managed --> marker)"
else
    say "CLAUDE.md kept (no <!-- control:managed --> marker found -- edit out manually if you want it removed)"
fi

# Strip Control block from .gitignore
if [ -f .gitignore ] && grep -q "# --- Control framework ---" .gitignore; then
    sed -i.bak '/# --- Control framework ---/,/# --- \/Control ---/d' .gitignore
    rm -f .gitignore.bak
    say "Cleaned .gitignore"
fi

say "Control uninstalled. Commit the removal when ready: git commit -am 'chore: remove Control framework'"
