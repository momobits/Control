#Requires -Version 5.0
<#
.SYNOPSIS
    Control framework uninstaller (PowerShell edition)

.DESCRIPTION
    Removes the entire .control/ directory, Control-managed files in .claude/,
    and root-level framework files. Leaves docs/ (project-owned), git history, and code intact.

.PARAMETER TargetDir
    Directory to remove Control from. Defaults to current directory.

.PARAMETER Force
    Skip the confirmation prompt.
#>

param(
    [string]$TargetDir = $PWD.Path,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host "[control-uninstall] $msg" }
function Die($msg) { Write-Host "[control-uninstall] ERROR: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $TargetDir)) { Die "target directory does not exist: $TargetDir" }
$TargetDir = (Resolve-Path $TargetDir).Path

if (-not (Test-Path (Join-Path $TargetDir '.control'))) {
    Say "No Control install detected at $TargetDir"
    exit 0
}

Write-Host @"
This will remove the Control framework from:
  $TargetDir

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

"@

if (-not $Force) {
    $ans = Read-Host 'Proceed? [y/N]'
    if ($ans -notmatch '^(y|Y|yes|YES|Yes)$') {
        Say "Aborted."
        exit 1
    }
}

Push-Location $TargetDir
try {
    Remove-Item -Recurse -Force .control -ErrorAction SilentlyContinue

    $filesToRemove = @(
        '.claude/settings.json',
        '.claude/hooks/pre-compact-dump.sh',
        '.claude/hooks/session-start-load.sh',
        '.claude/hooks/session-end-commit.sh',
        '.claude/hooks/stop-snapshot.sh',
        '.claude/hooks/prune-snapshots.sh',
        '.claude/hooks/regenerate-next-md.sh',
        # PowerShell hook ports (I5)
        '.claude/hooks/pre-compact-dump.ps1',
        '.claude/hooks/session-start-load.ps1',
        '.claude/hooks/session-end-commit.ps1',
        '.claude/hooks/stop-snapshot.ps1',
        '.claude/hooks/prune-snapshots.ps1',
        '.claude/hooks/regenerate-next-md.ps1',
        '.claude/commands/bootstrap.md',
        '.claude/commands/control-next.md',          # legacy alias (removed v2.1; clean up old installs)
        '.claude/commands/session-start.md',
        '.claude/commands/session-end.md',
        '.claude/commands/work-next.md',
        '.claude/commands/new-issue.md',
        '.claude/commands/close-issue.md',
        '.claude/commands/new-adr.md',
        '.claude/commands/new-spec-artifact.md',     # legacy alias (removed v2.1; clean up old installs)
        '.claude/commands/spec-amend.md',
        '.claude/commands/phase-close.md',
        '.claude/commands/validate.md',
        '.control/PROJECT_PROTOCOL.md'
    )
    foreach ($f in $filesToRemove) {
        Remove-Item -Force $f -ErrorAction SilentlyContinue
    }

    foreach ($d in @('.claude/commands', '.claude/hooks', '.claude')) {
        if ((Test-Path $d) -and -not (Get-ChildItem $d -Force)) {
            Remove-Item -Force $d -ErrorAction SilentlyContinue
        }
    }

    # --- .githooks/ -- remove Control's commit-msg only (preserve user-added hooks) ---
    if ((Test-Path '.githooks/commit-msg') -and (Select-String -Path '.githooks/commit-msg' -SimpleMatch 'control:commit-msg' -Quiet -ErrorAction SilentlyContinue)) {
        Remove-Item -Force '.githooks/commit-msg' -ErrorAction SilentlyContinue
        if ((Test-Path '.githooks') -and -not (Get-ChildItem '.githooks' -Force)) {
            Remove-Item -Force '.githooks' -ErrorAction SilentlyContinue
        }
    }

    # --- core.hooksPath -- revert only if Control set it ---
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $hooksPath = & git config --local --get core.hooksPath 2>$null
        if ($hooksPath -and $hooksPath.Trim() -eq '.githooks') {
            & git config --local --unset core.hooksPath 2>$null | Out-Null
            Say "Unset core.hooksPath (was .githooks -- set by Control)"
        }
    } finally {
        $ErrorActionPreference = $prevPref
    }

    if ((Test-Path 'CLAUDE.md') -and (Select-String -Path 'CLAUDE.md' -SimpleMatch '<!-- control:managed -->' -Quiet -ErrorAction SilentlyContinue)) {
        Remove-Item -Force 'CLAUDE.md'
        Say "Removed CLAUDE.md (bore the <!-- control:managed --> marker)"
    } else {
        Say "CLAUDE.md kept (no <!-- control:managed --> marker found -- edit out manually if you want it removed)"
    }

    if ((Test-Path .gitignore) -and (Select-String -Path .gitignore -SimpleMatch '# --- Control framework ---' -Quiet -ErrorAction SilentlyContinue)) {
        $lines = Get-Content .gitignore
        $out = New-Object System.Collections.Generic.List[string]
        $inControlBlock = $false
        foreach ($line in $lines) {
            if ($line -match '^# --- Control framework ---') { $inControlBlock = $true; continue }
            if ($inControlBlock -and $line -match '^# --- /Control ---') { $inControlBlock = $false; continue }
            if (-not $inControlBlock) { $out.Add($line) }
        }
        Set-Content -Path .gitignore -Value $out
        Say "Cleaned .gitignore"
    }

    Say "Control uninstalled. Commit the removal when ready: git commit -am 'chore: remove Control framework'"
}
finally {
    Pop-Location
}
