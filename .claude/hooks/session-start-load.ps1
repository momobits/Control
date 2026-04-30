#Requires -Version 5.0
# Control hook: SessionStart (PowerShell port of session-start-load.sh).
# Fires at the beginning of every Claude Code session.
# Injects the session-start protocol into context so Claude bootstraps automatically.
#
# Mirrors .claude/hooks/session-start-load.sh byte-for-byte in semantics. See
# .relay/issues/windows_powershell_hook_parity.md (I5.5) for the contract.
#
# Drift detection block (I2): 5 emission cases preserved -- missing / template-form /
# unparseable / field-mismatch / summary. Bootstrap heredoc: byte-equivalent to bash
# cat <<EOF output (post-M3 fix: CRLF -> LF normalization).
#
# Quadruplication contract (extends F12): runbook + slash command + bash hook
# heredoc + this PS hook heredoc all stay byte-equivalent. Future 5c changes
# update all four files in same diff.

$ErrorActionPreference = 'Continue'   # bash uses `|| true` per-command; mirror

$failOnError = $false
if (Test-Path '.control/config.sh') {
    Get-Content '.control/config.sh' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '^CONTROL_FAIL_ON_HOOK_ERROR=true') { $failOnError = $true }
    }
}

try {
    # --- Git state capture (mirrors bash L8-23) ---
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'

    $latestSnap = (Get-ChildItem '.control/snapshots' -Filter 'STATE-*.md' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    if (-not $latestSnap) { $latestSnap = '' }

    $gitBranch = (& git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $gitBranch) { $gitBranch = 'not-a-git-repo' }

    & git rev-parse HEAD 2>$null | Out-Null
    $headOK = ($LASTEXITCODE -eq 0)
    if ($headOK) {
        $gitLast = (& git log -1 --oneline 2>$null)
        & git diff-index --quiet HEAD -- 2>$null
        $diffExit = $LASTEXITCODE
        $porcelain = (& git status --porcelain 2>$null)
        $gitDirty = if (($diffExit -eq 0) -and (-not $porcelain)) { 'clean' } else { 'DIRTY' }
        $lastTag = (& git describe --tags --abbrev=0 2>$null)
        if (-not $lastTag) { $lastTag = 'none' }
    } else {
        $gitLast = '(no commits yet)'
        $gitDirty = 'n/a (no HEAD)'
        $lastTag = 'none'
    }

    $ErrorActionPreference = $prevPref

    # --- Drift detection (Issue I2 contract: 5 emission cases preserved) ---
    $stateFile = '.control/progress/STATE.md'
    $driftLines = @()

    function Get-StateField($label) {
        if (-not (Test-Path $stateFile)) { return '' }
        $line = Select-String -Path $stateFile -Pattern "^- \*\*${label}:\*\*" -List | Select-Object -First 1
        if (-not $line) { return '' }
        # sed -E "s/^- \*\*${label}:\*\* *//" + tr -d '\r'
        return ($line.Line -replace "^- \*\*${label}:\*\* *", '' -replace "`r", '')
    }

    if (-not (Test-Path $stateFile)) {
        # case (a) missing
        $driftLines = @('[DRIFT] STATE.md missing -- run /bootstrap')
    }
    elseif (Select-String -Path $stateFile -Pattern '<short-sha>|<YYYY-MM-DD>|<sha>' -Quiet) {
        # case (b) template form
        $driftLines = @('[DRIFT] STATE.md is in template form -- run /bootstrap')
    }
    else {
        $stateBranch     = Get-StateField 'Branch'
        $stateLastCommit = Get-StateField 'Last commit'
        $stateUncomm     = Get-StateField 'Uncommitted changes'
        $stateLastTagRaw = Get-StateField 'Last phase tag'

        if (-not $stateBranch -and -not $stateLastCommit -and -not $stateUncomm -and -not $stateLastTagRaw) {
            # case (c) all 4 fields absent: schema rename or section deletion
            $driftLines = @('[DRIFT] STATE.md Git state section unparseable (parser-contract fields absent) -- run /validate')
        }
        else {
            $stateLastTag = ($stateLastTagRaw -replace '`', '').Split(' ')[0]
            $gitLastSha = if ($gitLast) { $gitLast.Split(' ')[0] } else { '' }

            # case (d) branch
            if ($stateBranch -and ($stateBranch -ne $gitBranch)) {
                $driftLines += "[DRIFT] STATE.md says branch=$stateBranch, actual=$gitBranch"
            }
            # case (e) commit
            if ($stateLastCommit -and $gitLastSha -and (-not $stateLastCommit.Contains($gitLastSha))) {
                $driftLines += "[DRIFT] STATE.md says last commit=`"$stateLastCommit`", actual=$gitLast"
            }
            # case (f) uncommitted (special-case: literal `none` <-> tree clean)
            if (($stateUncomm -eq 'none') -and ($gitDirty -ne 'clean')) {
                $driftLines += "[DRIFT] STATE.md says uncommitted=none, actual=$gitDirty"
            }
            # case (g) tag
            if ($stateLastTag -and ($stateLastTag -ne $lastTag)) {
                $driftLines += "[DRIFT] STATE.md says last tag=$stateLastTag, actual=$lastTag"
            }
            # summary line on any field-level drift
            if ($driftLines.Count -gt 0) {
                $driftLines += '[DRIFT] Verify and update STATE.md before proceeding.'
            }
        }
    }

    if ($driftLines.Count -gt 0) {
        # M3 fix extension: WriteLine emits CRLF on Windows; bash `printf '%s\n\n'`
        # emits LF. Use Write + explicit `n to keep [DRIFT] lines byte-equivalent.
        $driftLines | ForEach-Object { [Console]::Out.Write($_ + "`n") }
        [Console]::Out.Write("`n")   # matches bash `printf '%s\n\n'`
    }

    # --- Bootstrap heredoc (byte-equivalent to bash L82-111 incl. F12.3 5c paragraph) ---
    $snapDisplay = if ($latestSnap) { $latestSnap } else { 'none' }
    $heredoc = @"
[control:SessionStart] Bootstrap

Before accepting user input, run the session-start protocol:

1. Read .control/progress/STATE.md
2. Read .control/progress/next.md (last session's handoff, if present)
3. Read the current phase README + steps (path in STATE.md)
4. List .control/issues/OPEN/ and flag current-phase blockers

Git state at session start (verify against STATE.md's Git state section):
  branch: $gitBranch
  last: $gitLast
  working tree: $gitDirty
  last tag: $lastTag

Latest PreCompact snapshot: $snapDisplay

After reading, report the standard status block and wait for the user's go
before editing any code. If [DRIFT] lines were emitted above, surface them
in the status block under ``Git sync:`` and pause for operator reconciliation
before reporting -- do not silently proceed.

After emitting the status block (and before waiting for the user's go to
begin code edits), read .claude/commands/control-next.md, apply its
priority decision tree against current state, and emit "Recommended
next: <command>" as a follow-up line. Skip silently if
.claude/commands/control-next.md does not exist, or if a design-decision
expansion already fired this turn (Step 5b takes precedence over Step 5c).
"@

    # M3 fix: normalize CRLF -> LF before stdout. PS here-strings on Windows use
    # OS-native line endings (CRLF); bash heredoc uses LF on Git Bash for Windows.
    # Use Write (no auto-newline) + explicit final LF to match bash's trailing newline.
    $heredocLF = $heredoc -replace "`r`n", "`n"
    [Console]::Out.Write($heredocLF + "`n")
}
catch {
    [Console]::Error.WriteLine("[control:SessionStart] ERROR: $_")
    if ($failOnError) { throw } else { exit 0 }
}
