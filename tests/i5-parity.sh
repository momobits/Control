#!/usr/bin/env bash
# tests/i5-parity.sh — Verification matrix for I5 (Windows PowerShell hook parity).
#
# Authored as the test-first foundation per the plan in
# .relay/issues/windows_powershell_hook_parity.md (Step 1 / I5.0).
#
# Usage:
#   bash tests/i5-parity.sh                # run all tests; first-failure-exit
#   bash tests/i5-parity.sh --only t0      # run T0 only
#   bash tests/i5-parity.sh --only t3      # run all T3 cases (drift detection matrix)
#   bash tests/i5-parity.sh --perf         # include T-perf advisory test
#
# Test groups:
#   T0      static syntax (bash -n + PS parser on every hook)
#   T1      markers.log byte-equivalence per hook (LF, no BOM, exact format)
#   T2      snapshot file naming
#   T3 a-h  drift detection 8-case matrix per I2 verification report
#   T4      stop hook bucketed prune (12 -> 10 retained)
#   T5      stop hook restore drill (corrupt -> restore -> bytes match)
#   T6      markers.log chronological order (precompact / stop / sessionend)
#   T7      bootstrap heredoc byte-equivalence (F12 quadruplication contract)
#   T8      settings.json runtime selection at install
#   T9      uninstall completeness (mixed-runtime install -> all hooks removed)
#   T10     doc grep (README + PROJECT_PROTOCOL.md)
#   T-perf  Stop hook 100 cmp-deduped fires under 5ms mean (advisory)
#
# This harness is part of the source repo only -- not propagated to operator
# installs by setup.sh / setup.ps1 (which scope to .claude/, .control/, .githooks/).

set -uo pipefail   # NOT -e: collect failures explicitly

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# --- result counters ---
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FIRST_FAILURE=""

# --- scratch tracking (cleanup at exit) ---
SCRATCHES=()
trap 'for d in "${SCRATCHES[@]}"; do [ -d "$d" ] && rm -rf "$d"; done' EXIT

say()      { printf "[i5-parity] %s\n" "$*"; }
log_pass() { printf "[i5-parity] PASS: %s\n" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { printf "[i5-parity] FAIL: %s\n" "$*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); [ -z "$FIRST_FAILURE" ] && FIRST_FAILURE="$*"; }
log_skip() { printf "[i5-parity] SKIP: %s\n" "$*"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

scratch_dir() {
    local d
    d=$(mktemp -d -t i5-parity.XXXXXX)
    SCRATCHES+=("$d")
    echo "$d"
}

setup_scratch() {
    local scratch="$1"
    mkdir -p "$scratch/.claude/hooks" "$scratch/.control/progress" "$scratch/.control/snapshots"
    cp "$REPO_ROOT/.claude/hooks/"*.sh "$scratch/.claude/hooks/" 2>/dev/null || true
    find "$REPO_ROOT/.claude/hooks/" -maxdepth 1 -name '*.ps1' -exec cp {} "$scratch/.claude/hooks/" \; 2>/dev/null || true
    cp "$REPO_ROOT/.control/config.sh" "$scratch/.control/config.sh"
    chmod +x "$scratch/.claude/hooks/"*.sh 2>/dev/null || true
    (cd "$scratch" \
        && git init --quiet \
        && git config user.email 'test@example.com' \
        && git config user.name 'Test' \
        && git config commit.gpgsign false) >/dev/null 2>&1
}

# Write a STATE.md to scratch with the four parser-contract Git-state fields.
# Args: scratch_dir branch commit uncommitted last_tag
write_state_md() {
    local d="$1" branch="$2" commit="$3" uncommitted="$4" last_tag="$5"
    cat > "$d/.control/progress/STATE.md" <<EOF
# Project State

**Last updated:** 2026-04-30 12:00 UTC by test
**Current phase:** test
**Current step:** 1.1
**Status:** test

## Git state
- **Branch:** $branch
- **Last commit:** $commit
- **Uncommitted changes:** $uncommitted
- **Last phase tag:** $last_tag
EOF
}

# Detect a PowerShell interpreter.
PS_CMD=""
if command -v powershell.exe >/dev/null 2>&1; then PS_CMD="powershell.exe"
elif command -v powershell >/dev/null 2>&1; then  PS_CMD="powershell"
elif command -v pwsh >/dev/null 2>&1; then        PS_CMD="pwsh"
fi

require_ps() {
    if [ -z "$PS_CMD" ]; then
        log_skip "$1: no PowerShell interpreter on PATH"
        return 1
    fi
    return 0
}

require_ps_file() {
    local rel="$1" desc="$2"
    if [ ! -f "$REPO_ROOT/$rel" ]; then
        log_fail "$desc: MISSING $rel (intentional failing-test baseline before I5 ports land)"
        return 1
    fi
    return 0
}

has_cr() {
    # Note: avoid `grep -c $'\r'` inside $() -- bash quirk eats CR in subst,
    # making grep match the empty pattern (every line). Use tr to count bytes.
    local f="$1"
    [ -f "$f" ] || return 1
    local n
    n=$(tr -cd '\r' < "$f" | wc -c | tr -d ' ')
    [ "$n" -gt 0 ]
}

has_bom() {
    local f="$1"
    [ -f "$f" ] || return 1
    [ "$(head -c 3 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo '')" = "efbbbf" ]
}

# ============================================================
# T0 — static syntax
# ============================================================
t0_syntax() {
    local missing=0 errs=0
    for f in "$REPO_ROOT/.claude/hooks/"*.sh; do
        [ -f "$f" ] || continue
        if ! bash -n "$f" 2>&1; then
            log_fail "T0: bash -n failed for $(basename "$f")"
            errs=$((errs+1))
        fi
    done
    local expected=( prune-snapshots.ps1 pre-compact-dump.ps1 session-end-commit.ps1 stop-snapshot.ps1 session-start-load.ps1 )
    for name in "${expected[@]}"; do
        local f="$REPO_ROOT/.claude/hooks/$name"
        if [ ! -f "$f" ]; then
            log_fail "T0: MISSING .claude/hooks/$name (intentional failing-test baseline before I5 ports land)"
            missing=$((missing+1))
            continue
        fi
        if [ -n "$PS_CMD" ]; then
            local winpath="$f"
            if [ "$PS_CMD" = "powershell.exe" ] && command -v cygpath >/dev/null 2>&1; then
                winpath=$(cygpath -w "$f")
            fi
            local out
            out=$("$PS_CMD" -NoProfile -Command "[void]([System.Management.Automation.Language.Parser]::ParseFile('${winpath//\\/\\\\}', [ref]\$null, [ref]\$null))" 2>&1)
            if [ $? -ne 0 ]; then
                log_fail "T0: PS parse failed for $name -- $out"
                errs=$((errs+1))
            fi
        else
            log_skip "T0: no PowerShell; parse skipped for $name"
        fi
    done
    [ $((missing + errs)) -eq 0 ] && log_pass "T0: static syntax (5 sh + 5 ps1)"
}

# ============================================================
# T1 — markers.log byte-equivalence
# ============================================================
_t1_format_ok() {
    local f="$1" event="$2" desc="$3"
    [ -f "$f" ] || { log_fail "$desc: markers.log absent"; return 1; }
    if has_cr "$f"; then log_fail "$desc: CR in markers.log (CRLF leak; should be LF-only)"; return 1; fi
    if has_bom "$f"; then log_fail "$desc: UTF-8 BOM in markers.log"; return 1; fi
    local pat
    case "$event" in
        precompact|sessionend) pat="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z  ${event}  snapshot_id=[0-9]{8}-[0-9]{6}  files=STATE\\.md,journal\\.md,next\\.md$" ;;
        stop) pat="^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z  stop  snapshot_id=[0-9]{8}-[0-9]{6}$" ;;
    esac
    if ! grep -qE "$pat" "$f"; then
        log_fail "$desc: markers.log doesn't match expected format"
        cat "$f" >&2
        return 1
    fi
    return 0
}

t1_markers_pre() {
    require_ps_file ".claude/hooks/pre-compact-dump.ps1" "T1 PreCompact" || return
    require_ps "T1 PreCompact" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123 test" "none" "none"
    echo "j" > "$B/.control/progress/journal.md"; echo "n" > "$B/.control/progress/next.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/pre-compact-dump.ps1) >/dev/null 2>&1
    _t1_format_ok "$B/.control/snapshots/markers.log" "precompact" "T1 PreCompact PS" \
        && log_pass "T1 PreCompact: markers.log format (LF, no BOM, ISO8601 + event + files)"
}

t1_markers_se() {
    require_ps_file ".claude/hooks/session-end-commit.ps1" "T1 SessionEnd" || return
    require_ps "T1 SessionEnd" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123 test" "none" "none"
    echo "j" > "$B/.control/progress/journal.md"; echo "n" > "$B/.control/progress/next.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/session-end-commit.ps1) >/dev/null 2>&1
    _t1_format_ok "$B/.control/snapshots/markers.log" "sessionend" "T1 SessionEnd PS" \
        && log_pass "T1 SessionEnd: markers.log format"
}

t1_markers_stop() {
    require_ps_file ".claude/hooks/stop-snapshot.ps1" "T1 Stop" || return
    require_ps "T1 Stop" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123 test" "none" "none"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/stop-snapshot.ps1) >/dev/null 2>&1
    _t1_format_ok "$B/.control/snapshots/markers.log" "stop" "T1 Stop PS" \
        && log_pass "T1 Stop: markers.log format (no files= clause per I3.5)"
}

# ============================================================
# T2 — snapshot file naming
# ============================================================
t2_naming_pre() {
    require_ps_file ".claude/hooks/pre-compact-dump.ps1" "T2 PreCompact" || return
    require_ps "T2 PreCompact" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123" "none" "none"
    echo "j" > "$B/.control/progress/journal.md"; echo "n" > "$B/.control/progress/next.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/pre-compact-dump.ps1) >/dev/null 2>&1
    local errs=0
    for prefix in STATE journal next; do
        local n
        n=$(find "$B/.control/snapshots/" -maxdepth 1 -name "${prefix}-[0-9]*.md" 2>/dev/null | wc -l)
        if [ "$n" -ne 1 ]; then
            log_fail "T2 PreCompact: expected 1 ${prefix}-<TS>.md, got $n"
            errs=$((errs+1))
        fi
    done
    [ $errs -eq 0 ] && log_pass "T2 PreCompact: snapshot file naming (STATE/journal/next-<TS>.md)"
}

t2_naming_se() {
    require_ps_file ".claude/hooks/session-end-commit.ps1" "T2 SessionEnd" || return
    require_ps "T2 SessionEnd" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123" "none" "none"
    echo "j" > "$B/.control/progress/journal.md"; echo "n" > "$B/.control/progress/next.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/session-end-commit.ps1) >/dev/null 2>&1
    local errs=0
    for prefix in STATE journal next; do
        local n
        n=$(find "$B/.control/snapshots/" -maxdepth 1 -name "sessionend-${prefix}-[0-9]*.md" 2>/dev/null | wc -l)
        if [ "$n" -ne 1 ]; then
            log_fail "T2 SessionEnd: expected 1 sessionend-${prefix}-<TS>.md, got $n"
            errs=$((errs+1))
        fi
    done
    [ $errs -eq 0 ] && log_pass "T2 SessionEnd: snapshot file naming (sessionend-{STATE,journal,next}-<TS>.md)"
}

# ============================================================
# T3 — drift detection 8-case matrix
# ============================================================
_t3_run() {
    local scratch="$1"
    (cd "$scratch" && "$PS_CMD" -NoProfile -File .claude/hooks/session-start-load.ps1) 2>&1
}

# NOTE: v2.0 hook output replaced legacy "[DRIFT] ..." prose lines with
# structured "[control:drift]" blocks containing a `type:` field plus
# type-specific fields (e.g. expected/actual for *-mismatch types). The
# v1.4 summary line ("Verify and update STATE.md before proceeding.") was
# removed -- Claude now narrates the drift instead. Tests below assert the
# new block-shape contract.

# (a) STATE.md missing
t3_drift_a() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3a missing" || return
    require_ps "T3a missing" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    rm -f "$B/.control/progress/STATE.md"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: state-md-missing"; then
        log_pass "T3a (missing): emits [control:drift] type=state-md-missing"
    else
        log_fail "T3a (missing): drift block absent -- got: $(echo "$out" | head -3)"
    fi
}

# (b) template form
t3_drift_b() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3b template" || return
    require_ps "T3b template" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    cp "$FIXTURES_DIR/state-template.md" "$B/.control/progress/STATE.md"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: state-md-template"; then
        log_pass "T3b (template form): emits [control:drift] type=state-md-template"
    else
        log_fail "T3b (template form): drift block absent -- got: $(echo "$out" | head -3)"
    fi
}

# (c) all 4 fields absent (unparseable)
t3_drift_c() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3c unparseable" || return
    require_ps "T3c unparseable" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    cp "$FIXTURES_DIR/state-unparseable.md" "$B/.control/progress/STATE.md"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: state-md-unparseable"; then
        log_pass "T3c (unparseable): emits [control:drift] type=state-md-unparseable"
    else
        log_fail "T3c (unparseable): drift block absent -- got: $(echo "$out" | head -3)"
    fi
}

# (d) branch skew
t3_drift_d() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3d branch" || return
    require_ps "T3d branch" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "wrongbranch" "abc123" "none" "none"
    (cd "$B" && git add . && git commit --quiet -m init) >/dev/null 2>&1
    local actual_branch; actual_branch=$(cd "$B" && git rev-parse --abbrev-ref HEAD)
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: branch-mismatch" \
       && echo "$out" | grep -qF "expected: wrongbranch" \
       && echo "$out" | grep -qF "actual: ${actual_branch}"; then
        log_pass "T3d (branch skew): emits branch-mismatch w/ expected=wrongbranch actual=${actual_branch}"
    else
        log_fail "T3d (branch skew): block absent or wrong -- got: $(echo "$out" | head -10)"
    fi
}

# (e) commit skew
t3_drift_e() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3e commit" || return
    require_ps "T3e commit" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    (cd "$B" && git add . && git commit --quiet --allow-empty -m "real commit") >/dev/null 2>&1
    local actual_branch; actual_branch=$(cd "$B" && git rev-parse --abbrev-ref HEAD)
    write_state_md "$B" "$actual_branch" "deadbeef stale claim" "none" "none"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: commit-mismatch" \
       && echo "$out" | grep -qF "expected: deadbeef stale claim"; then
        log_pass "T3e (commit skew): emits commit-mismatch w/ expected=deadbeef..."
    else
        log_fail "T3e (commit skew): block absent or wrong -- got: $(echo "$out" | head -10)"
    fi
}

# (f) uncommitted skew (claim=none, actual=dirty)
t3_drift_f() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3f uncommitted" || return
    require_ps "T3f uncommitted" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    (cd "$B" && git add . && git commit --quiet --allow-empty -m init) >/dev/null 2>&1
    local actual_branch; actual_branch=$(cd "$B" && git rev-parse --abbrev-ref HEAD)
    local actual_sha; actual_sha=$(cd "$B" && git log -1 --oneline)
    write_state_md "$B" "$actual_branch" "$actual_sha" "none" "none"
    # Make tree dirty
    echo "dirty" > "$B/dirty.txt"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: uncommitted-mismatch" \
       && echo "$out" | grep -qF "expected: none" \
       && echo "$out" | grep -qF "actual: dirty"; then
        log_pass "T3f (uncommitted skew): emits uncommitted-mismatch w/ expected=none actual=dirty"
    else
        log_fail "T3f (uncommitted skew): block absent or wrong -- got: $(echo "$out" | head -10)"
    fi
}

# (g) tag skew
t3_drift_g() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3g tag" || return
    require_ps "T3g tag" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    (cd "$B" && git add . && git commit --quiet --allow-empty -m init && git tag real-tag) >/dev/null 2>&1
    local actual_branch; actual_branch=$(cd "$B" && git rev-parse --abbrev-ref HEAD)
    local actual_sha; actual_sha=$(cd "$B" && git log -1 --oneline)
    write_state_md "$B" "$actual_branch" "$actual_sha" "none" "stale-tag"
    local out; out=$(_t3_run "$B")
    if echo "$out" | grep -qF "type: tag-mismatch" \
       && echo "$out" | grep -qF "expected: stale-tag" \
       && echo "$out" | grep -qF "actual: real-tag"; then
        log_pass "T3g (tag skew): emits tag-mismatch w/ expected=stale-tag actual=real-tag"
    else
        log_fail "T3g (tag skew): block absent or wrong -- got: $(echo "$out" | head -10)"
    fi
}

# (i) source-repo sentinel suppresses ALL drift (v2.0 / cycle 5a / C.5)
t3_drift_i() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3i sentinel" || return
    require_ps "T3i sentinel" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    cp "$FIXTURES_DIR/state-template.md" "$B/.control/progress/STATE.md"
    # Create sentinel BEFORE running hook
    : > "$B/.control/.is-source-repo"
    local out; out=$(_t3_run "$B")
    # Should emit NO [control:drift] blocks. Match block opener at line start
    # (the literal "[control:drift]" appears in the tail prose too).
    local n_blocks; n_blocks=$(echo "$out" | grep -cE "^\[control:drift\]$")
    if [ "$n_blocks" -eq 0 ]; then
        log_pass "T3i (sentinel): source-repo sentinel suppresses all drift (template state.md present)"
    else
        log_fail "T3i (sentinel): drift NOT suppressed -- found $n_blocks block opener line(s)"
    fi
}

# (h) all 4 skewed -> 4 [control:drift] blocks (no summary line in v2.0)
t3_drift_h() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T3h all-skew" || return
    require_ps "T3h all-skew" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    (cd "$B" && git add . && git commit --quiet --allow-empty -m init && git tag real-tag) >/dev/null 2>&1
    write_state_md "$B" "wrongbranch" "deadbeef wrong" "none" "stale-tag"
    echo "dirty" > "$B/dirty.txt"
    local out; out=$(_t3_run "$B")
    local n_blocks; n_blocks=$(echo "$out" | grep -cF "[control:drift]")
    # Expect 4 field-mismatch blocks. Open-tag count == close-tag count, so
    # divide by 2 to get block count.
    local n_open; n_open=$(echo "$out" | grep -cF "^\[control:drift\]" 2>/dev/null || echo 0)
    local n_type; n_type=$(echo "$out" | grep -cE "^type: (branch|commit|uncommitted|tag)-mismatch")
    if [ "$n_type" -eq 4 ]; then
        log_pass "T3h (all-skew): emits 4 mismatch [control:drift] blocks"
    else
        log_fail "T3h (all-skew): expected 4 *-mismatch type lines; got $n_type -- $(echo "$out" | grep -E '^type:')"
    fi
}

# ============================================================
# T4 — stop bucketed prune
# ============================================================
t4_bucket_prune() {
    require_ps_file ".claude/hooks/prune-snapshots.ps1" "T4 bucket-prune" || return
    require_ps "T4 bucket-prune" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    local i
    for i in $(seq 1 12); do
        local ts; ts=$(printf "20260101-%06d" $i)
        echo "snap $i" > "$B/.control/snapshots/stop-$ts.md"
        # Mtimes need to be distinct for sort order
        sleep 0.01
        touch "$B/.control/snapshots/stop-$ts.md"
    done
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/prune-snapshots.ps1 -Bucket stop -Count 10) >/dev/null 2>&1
    local n; n=$(find "$B/.control/snapshots/" -maxdepth 1 -name 'stop-*.md' | wc -l)
    if [ "$n" -eq 10 ]; then
        log_pass "T4: bucketed prune retained 10 of 12 stop-*.md"
    else
        log_fail "T4: bucketed prune expected 10 retained, got $n"
    fi
}

# ============================================================
# T5 — stop restore drill
# ============================================================
t5_restore() {
    require_ps_file ".claude/hooks/stop-snapshot.ps1" "T5 restore" || return
    require_ps "T5 restore" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123" "none" "none"
    cp "$B/.control/progress/STATE.md" "$B/baseline.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/stop-snapshot.ps1) >/dev/null 2>&1
    local stopfile; stopfile=$(find "$B/.control/snapshots/" -maxdepth 1 -name 'stop-*.md' | head -1)
    if [ -z "$stopfile" ]; then
        log_fail "T5: stop snapshot not created"
        return
    fi
    echo "GARBAGE LINE" >> "$B/.control/progress/STATE.md"
    cp "$stopfile" "$B/.control/progress/STATE.md"
    if cmp -s "$B/.control/progress/STATE.md" "$B/baseline.md"; then
        log_pass "T5: restore drill — corrupted STATE.md restored byte-identical to baseline"
    else
        log_fail "T5: post-restore bytes differ from baseline"
    fi
}

# ============================================================
# T6 — markers.log chronological order
# ============================================================
t6_chrono() {
    require_ps_file ".claude/hooks/pre-compact-dump.ps1" "T6 chrono" || return
    require_ps_file ".claude/hooks/stop-snapshot.ps1" "T6 chrono" || return
    require_ps_file ".claude/hooks/session-end-commit.ps1" "T6 chrono" || return
    require_ps "T6 chrono" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123" "none" "none"
    echo "j" > "$B/.control/progress/journal.md"; echo "n" > "$B/.control/progress/next.md"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/pre-compact-dump.ps1) >/dev/null 2>&1
    sleep 1
    echo "x" >> "$B/.control/progress/STATE.md"  # change so Stop's cmp doesn't dedup
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/stop-snapshot.ps1) >/dev/null 2>&1
    sleep 1
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/session-end-commit.ps1) >/dev/null 2>&1
    local events; events=$(awk -F'  ' '{print $2}' "$B/.control/snapshots/markers.log" | tr '\n' ' ')
    if [ "$events" = "precompact stop sessionend " ]; then
        log_pass "T6: markers.log chronological order (precompact / stop / sessionend)"
    else
        log_fail "T6: markers.log order wrong; expected 'precompact stop sessionend ', got '$events'"
    fi
}

# ============================================================
# T7 — bootstrap heredoc byte-equivalence (F12 quadruplication contract gate)
# ============================================================
t7_heredoc_diff() {
    require_ps_file ".claude/hooks/session-start-load.ps1" "T7 heredoc" || return
    require_ps "T7 heredoc" || return
    local A; A=$(scratch_dir); setup_scratch "$A"
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$A" "main" "abc123" "none" "none"
    write_state_md "$B" "main" "abc123" "none" "none"
    (cd "$A" && git add . && git commit --quiet -m init) >/dev/null 2>&1
    (cd "$B" && git add . && git commit --quiet -m init) >/dev/null 2>&1
    local A_OUT="$A/bash-stdout.txt" B_OUT="$B/ps-stdout.txt"
    (cd "$A" && bash .claude/hooks/session-start-load.sh > "$A_OUT") 2>/dev/null
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/session-start-load.ps1 > "$B_OUT") 2>/dev/null
    # M3 fix gate: PS stdout must NOT contain CR
    if has_cr "$B_OUT"; then
        log_fail "T7: PS heredoc emits CR (M3 fix not in place; expected LF-only)"
        return
    fi
    # Strip variable [control:state] field lines + entire [control:drift] blocks,
    # then diff the remaining fixed shell of the v2.0 output.
    local STRIP='/^branch:/d; /^last-commit-sha:/d; /^last-commit-subject:/d; /^working-tree:/d; /^last-tag:/d; /^latest-precompact:/d'
    # Drop drift blocks entirely (variable depending on STATE.md state)
    sed -e '/^\[control:drift\]/,/^\[\/control:drift\]/d' -e "$STRIP" "$A_OUT" | tr -d '\r' > "$A/fixed.txt"
    sed -e '/^\[control:drift\]/,/^\[\/control:drift\]/d' -e "$STRIP" "$B_OUT" | tr -d '\r' > "$B/fixed.txt"
    if diff -u "$A/fixed.txt" "$B/fixed.txt" >/dev/null; then
        # Confirm v2.0 tail pointer to runbook survived
        if grep -qF "Follow .claude/commands/session-start.md to bootstrap" "$B/fixed.txt"; then
            log_pass "T7: hook output byte-equivalent (v2.0 tail pointer present; PS = LF only)"
        else
            log_fail "T7: v2.0 runbook-pointer tail absent from PS hook output"
        fi
    else
        log_fail "T7: hook output diff non-empty; quadruplication contract violated"
        diff -u "$A/fixed.txt" "$B/fixed.txt" | head -30 >&2
    fi
}

# ============================================================
# T8 — settings.json runtime selection
# ============================================================
t8_install_select() {
    require_ps "T8 install-select" || return
    local SCRATCH; SCRATCH=$(scratch_dir)
    if ! "$PS_CMD" -NoProfile -File "$REPO_ROOT/setup.ps1" -TargetDir "$SCRATCH" >/dev/null 2>&1; then
        log_fail "T8: setup.ps1 install failed"
        return
    fi
    if [ ! -f "$SCRATCH/.claude/settings.json" ]; then
        log_fail "T8: settings.json absent post-install"
        return
    fi
    local cfg="$SCRATCH/.control/config.sh"
    # On this dev box bash is on PATH, so default install picks bash.
    if ! grep -qF '"command": "bash .claude/hooks/' "$SCRATCH/.claude/settings.json"; then
        log_fail "T8: settings.json doesn't have bash wiring (expected on Git-Bash-present box)"
        cat "$SCRATCH/.claude/settings.json" >&2
        return
    fi
    if ! grep -qF 'CONTROL_HOOK_RUNTIME=bash' "$cfg"; then
        log_fail "T8: config.sh missing CONTROL_HOOK_RUNTIME=bash line"
        return
    fi
    log_pass "T8: install with bash present -- settings.json bash-wired + config.sh CONTROL_HOOK_RUNTIME=bash"
}

# ============================================================
# T9 — uninstall completeness
# ============================================================
t9_uninstall() {
    require_ps "T9 uninstall" || return
    local SCRATCH; SCRATCH=$(scratch_dir)
    "$PS_CMD" -NoProfile -File "$REPO_ROOT/setup.ps1" -TargetDir "$SCRATCH" >/dev/null 2>&1 || {
        log_fail "T9: setup.ps1 install failed"; return
    }
    "$PS_CMD" -NoProfile -File "$REPO_ROOT/uninstall.ps1" -TargetDir "$SCRATCH" -Force >/dev/null 2>&1 || {
        log_fail "T9: uninstall.ps1 failed"; return
    }
    local n; n=$(find "$SCRATCH/.claude/" -maxdepth 2 \( -name '*.sh' -o -name '*.ps1' \) 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
        log_pass "T9: uninstall removes all hooks (sh + ps1)"
    else
        log_fail "T9: uninstall left $n hook files behind"
        find "$SCRATCH/.claude/" -maxdepth 2 \( -name '*.sh' -o -name '*.ps1' \) >&2
    fi
}

# ============================================================
# T10 — doc grep
# ============================================================
t10_doc() {
    local errs=0
    if grep -qF 'graceful degradation' "$REPO_ROOT/README.md"; then
        log_fail "T10: README.md still contains 'graceful degradation' (I5.8 should remove)"; errs=$((errs+1))
    fi
    if grep -qF 'will not function without bash' "$REPO_ROOT/README.md"; then
        log_fail "T10: README.md still contains 'will not function without bash' (I5.8 should remove)"; errs=$((errs+1))
    fi
    if ! grep -qF 'CONTROL_HOOK_RUNTIME' "$REPO_ROOT/README.md"; then
        log_fail "T10: README.md missing CONTROL_HOOK_RUNTIME (I5.8 should add)"; errs=$((errs+1))
    fi
    if ! grep -qF 'CONTROL_HOOK_RUNTIME' "$REPO_ROOT/.control/PROJECT_PROTOCOL.md"; then
        log_fail "T10: PROJECT_PROTOCOL.md missing CONTROL_HOOK_RUNTIME (I5.8 should add)"; errs=$((errs+1))
    fi
    if grep -qF 'POSIX bash, runnable on Windows via Git Bash' "$REPO_ROOT/.control/PROJECT_PROTOCOL.md"; then
        log_fail "T10: PROJECT_PROTOCOL.md still has 'POSIX bash, runnable on Windows via Git Bash' (I5.8 should replace)"; errs=$((errs+1))
    fi
    if ! grep -qF 'powershell -NoProfile' "$REPO_ROOT/.control/PROJECT_PROTOCOL.md"; then
        log_fail "T10: PROJECT_PROTOCOL.md missing 'powershell -NoProfile' (I5.8 should add)"; errs=$((errs+1))
    fi
    if ! grep -qiF 'quadruplication' "$REPO_ROOT/.control/PROJECT_PROTOCOL.md"; then
        log_fail "T10: PROJECT_PROTOCOL.md missing 'quadruplication' contract subsection (I5.8 should add)"; errs=$((errs+1))
    fi
    [ $errs -eq 0 ] && log_pass "T10: doc grep (README + PROJECT_PROTOCOL.md updated correctly)"
}

# ============================================================
# T-perf — Stop hook performance budget (advisory)
# ============================================================
t_perf() {
    require_ps_file ".claude/hooks/stop-snapshot.ps1" "T-perf" || return
    require_ps "T-perf" || return
    local B; B=$(scratch_dir); setup_scratch "$B"
    write_state_md "$B" "main" "abc123" "none" "none"
    (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/stop-snapshot.ps1) >/dev/null 2>&1
    local start_s end_s
    start_s=$(date +%s)
    local i
    for i in $(seq 1 100); do
        (cd "$B" && "$PS_CMD" -NoProfile -File .claude/hooks/stop-snapshot.ps1) >/dev/null 2>&1
    done
    end_s=$(date +%s)
    local total_ms=$(( (end_s - start_s) * 1000 ))
    local mean_ms=$((total_ms / 100))
    if [ "$mean_ms" -le 5 ]; then
        log_pass "T-perf: Stop hook 100 cmp-deduped fires, mean ~${mean_ms}ms (<= 5ms budget)"
    else
        log_skip "T-perf: Stop hook mean ~${mean_ms}ms > 5ms budget (advisory; PS cold-start dominates)"
    fi
}

# ============================================================
# Driver
# ============================================================
ALL_TESTS=(
    t0_syntax
    t1_markers_pre t1_markers_se t1_markers_stop
    t2_naming_pre t2_naming_se
    t3_drift_a t3_drift_b t3_drift_c t3_drift_d t3_drift_e t3_drift_f t3_drift_g t3_drift_h t3_drift_i
    t4_bucket_prune
    t5_restore
    t6_chrono
    t7_heredoc_diff
    t8_install_select
    t9_uninstall
    t10_doc
)

ONLY=""
WITH_PERF=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --perf) WITH_PERF=1; shift ;;
        --help|-h) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

SELECTED=()
if [ -n "$ONLY" ]; then
    for t in "${ALL_TESTS[@]}"; do
        case "$t" in
            "$ONLY"|"$ONLY"_*|"${ONLY}"*) SELECTED+=("$t") ;;
        esac
    done
else
    SELECTED=("${ALL_TESTS[@]}")
fi
[ "$WITH_PERF" -eq 1 ] && SELECTED+=(t_perf)

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "No tests matched pattern: $ONLY" >&2
    exit 2
fi

say "Running ${#SELECTED[@]} test(s)..."
for t in "${SELECTED[@]}"; do
    "$t" || true
    if [ "$FAIL_COUNT" -gt 0 ]; then
        say "First failure: $FIRST_FAILURE -- exiting per first-failure-exit policy"
        break
    fi
done

say "Results: $PASS_COUNT pass / $FAIL_COUNT fail / $SKIP_COUNT skip"
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
