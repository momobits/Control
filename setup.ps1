#Requires -Version 5.0
<#
.SYNOPSIS
    Control framework installer (PowerShell edition)

.DESCRIPTION
    Installs the Control framework into a target project directory.
    All Control-managed files land under .control/ and .claude/. The project's
    docs/ at the root is NOT touched -- that namespace belongs to project content.

.PARAMETER TargetDir
    Directory to install into. Defaults to current directory.

.PARAMETER Force
    Overwrite existing project-managed files (STATE.md, CLAUDE.md, etc.).

.PARAMETER Upgrade
    Refresh framework files only; leave project content alone.

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -TargetDir C:\projects\my-project
    .\setup.ps1 -Upgrade
#>

param(
    [string]$TargetDir = $PWD.Path,
    [switch]$Force,
    [switch]$Upgrade
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Say($msg) { Write-Host "[control-setup] $msg" }
function Die($msg) { Write-Host "[control-setup] ERROR: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path (Join-Path $ScriptDir '.claude'))) {
    Die "framework source not found at $ScriptDir -- run setup.ps1 from the control/ directory"
}
if (-not (Test-Path $TargetDir)) {
    Die "target directory does not exist: $TargetDir"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Die "git is required. Install Git for Windows (https://git-scm.com/) and retry."
}

$TargetDir = (Resolve-Path $TargetDir).Path
$ControlVersion = (Get-Content (Join-Path $ScriptDir 'VERSION')).Trim()

Say "Installing Control v$ControlVersion into $TargetDir"
if ($Upgrade) { Say "(upgrade mode -- framework files only, project content untouched)" }

Push-Location $TargetDir
try {
    if (-not (Test-Path .git)) {
        Say "Initialising git repository"
        git init --quiet
    }

    function Copy-ControlFile {
        param(
            [Parameter(Mandatory)][string]$Src,
            [Parameter(Mandatory)][string]$Dst,
            [Parameter(Mandatory)][ValidateSet('framework','project')][string]$Kind
        )
        $dstDir = Split-Path -Parent $Dst
        if ($dstDir -and -not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        }

        if (-not (Test-Path $Dst)) {
            Copy-Item -Path $Src -Destination $Dst
            Say "  + $Dst"
            return
        }

        switch ($Kind) {
            'framework' {
                if ($Upgrade -or $Force) {
                    Copy-Item -Path $Src -Destination $Dst -Force
                    Say "  ~ $Dst (updated)"
                } else {
                    Say "  = $Dst (exists -- use -Upgrade to update)"
                }
            }
            'project' {
                if ($Force) {
                    Copy-Item -Path $Src -Destination $Dst -Force
                    Say "  ~ $Dst (forced)"
                } else {
                    Say "  = $Dst (exists -- kept; use -Force to overwrite)"
                }
            }
        }
    }

    # .control/ framework area
    Say "Installing .control/"
    New-Item -ItemType Directory -Path ".control/snapshots" -Force | Out-Null
    Copy-ControlFile -Src (Join-Path $ScriptDir '.control/VERSION')   -Dst '.control/VERSION'   -Kind framework
    Copy-ControlFile -Src (Join-Path $ScriptDir '.control/config.sh') -Dst '.control/config.sh' -Kind project
    if (-not (Test-Path '.control/snapshots/.gitkeep')) {
        New-Item -ItemType File -Path '.control/snapshots/.gitkeep' -Force | Out-Null
    }

    # .claude/
    Say "Installing .claude/settings.json, commands, hooks"
    Copy-ControlFile -Src (Join-Path $ScriptDir '.claude/settings.json') -Dst '.claude/settings.json' -Kind framework

    Get-ChildItem (Join-Path $ScriptDir '.claude/commands/*.md') | ForEach-Object {
        Copy-ControlFile -Src $_.FullName -Dst ".claude/commands/$($_.Name)" -Kind framework
    }

    Get-ChildItem (Join-Path $ScriptDir '.claude/hooks/*.sh') | ForEach-Object {
        Copy-ControlFile -Src $_.FullName -Dst ".claude/hooks/$($_.Name)" -Kind framework
    }

    # Always-copy-both: PowerShell hook ports also installed (I5). The runtime
    # wired in .claude/settings.json is decided below by the bash-detection block.
    Get-ChildItem (Join-Path $ScriptDir '.claude/hooks/*.ps1') -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-ControlFile -Src $_.FullName -Dst ".claude/hooks/$($_.Name)" -Kind framework
    }

    # .githooks/ (git-side hooks; commit-msg shape enforcement)
    $githooksDir = Join-Path $ScriptDir '.githooks'
    if (Test-Path $githooksDir) {
        Say "Installing .githooks/"
        Get-ChildItem $githooksDir -File | ForEach-Object {
            Copy-ControlFile -Src $_.FullName -Dst ".githooks/$($_.Name)" -Kind framework
        }
    }

    # .control/ managed content
    if ($Upgrade) {
        Say "Upgrade mode: refreshing .control/templates/ and .control/runbooks/ only"
        Get-ChildItem (Join-Path $ScriptDir '.control/templates/*.md') | ForEach-Object {
            Copy-ControlFile -Src $_.FullName -Dst ".control/templates/$($_.Name)" -Kind framework
        }
        Get-ChildItem (Join-Path $ScriptDir '.control/runbooks/*.md') | ForEach-Object {
            Copy-ControlFile -Src $_.FullName -Dst ".control/runbooks/$($_.Name)" -Kind framework
        }
    } else {
        Say "Installing .control/ managed content"
        foreach ($d in @(
            '.control/architecture/decisions', '.control/architecture/interfaces',
            '.control/phases', '.control/progress',
            '.control/issues/OPEN', '.control/issues/RESOLVED',
            '.control/runbooks', '.control/templates',
            '.control/spec/artifacts'
        )) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }

        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/progress/STATE.md')           -Dst '.control/progress/STATE.md'           -Kind project
        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/progress/journal.md')         -Dst '.control/progress/journal.md'         -Kind project
        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/progress/next.md')            -Dst '.control/progress/next.md'            -Kind project
        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/architecture/overview.md')    -Dst '.control/architecture/overview.md'    -Kind project
        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/architecture/phase-plan.md')  -Dst '.control/architecture/phase-plan.md'  -Kind project

        Get-ChildItem (Join-Path $ScriptDir '.control/runbooks/*.md') | ForEach-Object {
            Copy-ControlFile -Src $_.FullName -Dst ".control/runbooks/$($_.Name)" -Kind framework
        }
        Get-ChildItem (Join-Path $ScriptDir '.control/templates/*.md') | ForEach-Object {
            Copy-ControlFile -Src $_.FullName -Dst ".control/templates/$($_.Name)" -Kind framework
        }

        # spec/ README (SPEC.md itself is populated by /bootstrap)
        $specReadme = Join-Path $ScriptDir '.control/templates/spec-readme.md'
        if (Test-Path $specReadme) {
            Copy-ControlFile -Src $specReadme -Dst '.control/spec/README.md' -Kind project
        }

        foreach ($gk in @(
            '.control/architecture/decisions/.gitkeep',
            '.control/issues/OPEN/.gitkeep',
            '.control/issues/RESOLVED/.gitkeep',
            '.control/phases/.gitkeep',
            '.control/spec/artifacts/.gitkeep'
        )) {
            if (-not (Test-Path $gk)) {
                New-Item -ItemType File -Path $gk -Force | Out-Null
            }
        }
    }

    # CLAUDE.md, .control/PROJECT_PROTOCOL.md at root
    Copy-ControlFile -Src (Join-Path $ScriptDir 'CLAUDE.md') -Dst 'CLAUDE.md' -Kind project
    if (Test-Path (Join-Path $ScriptDir '.control/PROJECT_PROTOCOL.md')) {
        Copy-ControlFile -Src (Join-Path $ScriptDir '.control/PROJECT_PROTOCOL.md') -Dst '.control/PROJECT_PROTOCOL.md' -Kind framework
    }

    # .gitignore
    $gitignoreMarker = '# --- Control framework ---'
    $needsUpdate = -not (Test-Path .gitignore) -or -not (Select-String -Path .gitignore -SimpleMatch $gitignoreMarker -Quiet -ErrorAction SilentlyContinue)
    if ($needsUpdate) {
        Say "Updating .gitignore"
        Add-Content -Path .gitignore -Value ""
        Add-Content -Path .gitignore -Value $gitignoreMarker
        Add-Content -Path .gitignore -Value ".control/snapshots/"
        Add-Content -Path .gitignore -Value ".claude/settings.local.json"
        Add-Content -Path .gitignore -Value "# --- /Control ---"
    }

    # Initial commit + tag
    function Invoke-GitSilent {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments=$true)][string[]]$GitArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            & git @GitArgs 2>&1 | Out-Null
            return $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prev
        }
    }

    function Invoke-GitCapture {
        [CmdletBinding()]
        param([Parameter(ValueFromRemainingArguments=$true)][string[]]$GitArgs)
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            $out = & git @GitArgs 2>$null
            return $out
        } finally {
            $ErrorActionPreference = $prev
        }
    }

    function Test-GitRef {
        param([string]$Ref)
        return ((Invoke-GitSilent 'rev-parse' '--verify' $Ref) -eq 0)
    }

    if ($Upgrade) {
        Say "Upgrade complete. Review changes with 'git status' and commit when ready."
    } else {
        $headExists = Test-GitRef 'HEAD'

        if ($headExists) {
            $porcelain = Invoke-GitCapture 'status' '--porcelain'
            if ($porcelain) {
                [void](Invoke-GitSilent 'add' '-A')
                [void](Invoke-GitSilent 'commit' '--quiet' '-m' "chore(install): install Control framework v$ControlVersion")
                Say "Committed: install Control framework v$ControlVersion"
            }
        } else {
            [void](Invoke-GitSilent 'add' '-A')
            [void](Invoke-GitSilent 'commit' '--quiet' '-m' "chore(install): scaffold project with Control framework v$ControlVersion")
            Say "Initial commit created"
        }

        if (-not (Test-GitRef 'protocol-initialised')) {
            [void](Invoke-GitSilent 'tag' 'protocol-initialised')
            Say "Tagged: protocol-initialised"
        }
    }

    # --- Hook runtime detection + settings.json rewrite (I5) ---
    # Decide which runtime wires the 4 Claude Code hooks at install time:
    #   - bash on PATH AND working ('exit 0' returns 0): wire bash hooks.
    #   - else: wire PowerShell hook ports (.ps1).
    # Operator can switch later by editing CONTROL_HOOK_RUNTIME in .control/config.sh
    # and rerunning setup. UPGRADE preserves the existing tunable value.
    function Test-BashWorks {
        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bashCmd) { return $false }
        try {
            $null = & bash -c 'exit 0' 2>&1                                   # behavioral check
            return ($LASTEXITCODE -eq 0)                                      # stub-bash on PATH would fail
        } catch {
            return $false                                                     # AntiVirus / ExecutionPolicy could block exec
        }
    }
    $bashAvailable = Test-BashWorks
    $existingRuntime = ''
    if (Test-Path '.control/config.sh') {
        $line = Select-String -Path '.control/config.sh' -Pattern '^CONTROL_HOOK_RUNTIME=(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($line) { $existingRuntime = ($line.Matches[0].Groups[1].Value).Trim() }
    }
    $runtime = if ($Upgrade -and $existingRuntime) { $existingRuntime }
               elseif ($bashAvailable) { 'bash' } else { 'powershell' }
    Say "Hook runtime: $runtime"

    $ext = if ($runtime -eq 'powershell') { 'ps1' } else { 'sh' }
    $cmdPrefix = if ($runtime -eq 'powershell') { 'powershell -NoProfile -File ' } else { 'bash ' }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $settingsContent = @"
{
  "hooks": {
    "PreCompact": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "${cmdPrefix}.claude/hooks/pre-compact-dump.${ext}" } ] }
    ],
    "SessionStart": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "${cmdPrefix}.claude/hooks/session-start-load.${ext}" } ] }
    ],
    "SessionEnd": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "${cmdPrefix}.claude/hooks/session-end-commit.${ext}" } ] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [ { "type": "command", "command": "${cmdPrefix}.claude/hooks/stop-snapshot.${ext}" } ] }
    ]
  }
}
"@
    [System.IO.File]::WriteAllText('.claude/settings.json', $settingsContent, $utf8NoBom)
    Say "Wrote .claude/settings.json (hook runtime: $runtime)"

    # Record CONTROL_HOOK_RUNTIME on fresh install only (kind=project; UPGRADE preserves).
    # M5 fix: AppendAllText with explicit `n -- avoids Add-Content's CRLF default
    # (config.sh is bash-sourced; CRLF would corrupt `. .control/config.sh`).
    if (-not $Upgrade -and -not $existingRuntime -and (Test-Path '.control/config.sh')) {
        [System.IO.File]::AppendAllText('.control/config.sh', "`nCONTROL_HOOK_RUNTIME=$runtime`n", $utf8NoBom)
        Say "Recorded CONTROL_HOOK_RUNTIME=$runtime in .control/config.sh"
    }
    # --- End hook runtime detection ---

    # --- wire core.hooksPath (skip if already set; preserves husky / pre-commit) ---
    # Idempotent: safe to re-run. -Upgrade intentionally skipped to preserve operator state.
    if (-not $Upgrade -and (Test-Path '.githooks/commit-msg')) {
        $existingHooksPath = (Invoke-GitCapture 'config' '--local' '--get' 'core.hooksPath')
        if ([string]::IsNullOrWhiteSpace($existingHooksPath)) {
            [void](Invoke-GitSilent 'config' '--local' 'core.hooksPath' '.githooks')
            Say "Wired commit-msg hook (core.hooksPath = .githooks)"
        } elseif ($existingHooksPath.Trim() -eq '.githooks') {
            Say "core.hooksPath already set to .githooks -- commit-msg hook active"
        } else {
            Write-Host "[control-setup] WARNING: core.hooksPath is already set to '$($existingHooksPath.Trim())' (likely husky / pre-commit / lefthook)." -ForegroundColor Yellow
            Write-Host "[control-setup] WARNING: Control's commit-msg hook NOT auto-wired. To enable: chain '.githooks/commit-msg' from your existing hooksPath dir, OR unset and rerun setup." -ForegroundColor Yellow
        }
    }

    $nestedSource = $ScriptDir.StartsWith($TargetDir, [StringComparison]::OrdinalIgnoreCase)
    if ($nestedSource -and -not $Upgrade) {
        Write-Host ""
        Say "Detected: the control/ source lives INSIDE this project."
        Say "If you don't plan to re-install, you can remove it: Remove-Item -Recurse -Force '$ScriptDir'"
    }

    Write-Host ""
    Write-Host "Control v$ControlVersion installed at $TargetDir"
    Write-Host ""
    Write-Host "Layout:"
    Write-Host "  CLAUDE.md                 -- auto-loaded every session"
    Write-Host "  .control/PROJECT_PROTOCOL.md       -- framework reference"
    Write-Host "  .control/                 -- all Control-managed files"
    Write-Host "    config.sh, VERSION, snapshots/"
    Write-Host "    progress/ architecture/ phases/ issues/ runbooks/ templates/ spec/"
    Write-Host "  .claude/                  -- commands, hooks, settings"
    Write-Host "  docs/                     -- UNTOUCHED (your project's own docs live here)"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. If you have a spec file: /bootstrap <path-to-spec>"
    Write-Host "     If you don't: /bootstrap (no args -- scans the codebase and prompts you)"
    Write-Host "  2. Review the bootstrap output"
    Write-Host "  3. Commit"
    Write-Host "  4. /session-start"
    Write-Host ""
    Write-Host "Run 'setup.ps1 -Upgrade' to update framework files without touching your project content."
    Write-Host ""
    Write-Host "Hook runtime: $runtime (set CONTROL_HOOK_RUNTIME in .control/config.sh"
    Write-Host "and rerun setup to switch). Both .sh and .ps1 hooks ship; .claude/settings.json"
    Write-Host "is wired to the chosen runtime."
}
finally {
    Pop-Location
}
