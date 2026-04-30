#Requires -Version 5.0
<#
.SYNOPSIS
    PowerShell launcher for tests/i5-parity.sh.

.DESCRIPTION
    Locates bash on PATH (Git Bash on Windows, /bin/bash on Linux/macOS-via-pwsh)
    and dispatches the bash test matrix. Pass-through for --only and --perf flags.

    Use this when running on a PS-only Windows host where you'd rather invoke from
    PowerShell than open Git Bash. The matrix itself is bash; the launcher is a
    convenience.

.EXAMPLE
    .\tests\i5-parity.ps1
    .\tests\i5-parity.ps1 -Only t0
    .\tests\i5-parity.ps1 -Perf
#>

param(
    [string]$Only = '',
    [switch]$Perf
)

$ErrorActionPreference = 'Stop'

$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd) {
    Write-Host "[i5-parity] ERROR: bash not on PATH. Install Git for Windows or run from a host with bash." -ForegroundColor Red
    exit 2
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$harness = Join-Path $scriptDir 'i5-parity.sh'

$bashArgs = @($harness)
if ($Only) { $bashArgs += '--only', $Only }
if ($Perf) { $bashArgs += '--perf' }

& bash @bashArgs
exit $LASTEXITCODE
