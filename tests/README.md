# tests/

Verification matrix for the Control framework. Currently scoped to **I5** (Windows PowerShell hook parity) — see `.relay/issues/windows_powershell_hook_parity.md` for the issue and plan that drove this harness.

This directory is part of the **source repo only**. It is NOT propagated to operator installs by `npx control-workflow init` (which scopes to `.claude/`, `.control/`, `.githooks/`, `CLAUDE.md`).

## Files

- **`i5-parity.sh`** — bash test harness, 11 test groups (T0–T10) + advisory `T-perf`. First-failure-exit policy. Cross-platform (Linux / macOS / Windows-via-Git-Bash).
- **`i5-parity.ps1`** — PowerShell launcher. Locates `bash` on PATH and dispatches the matrix.
- **`fixtures/`** — STATE.md variants for the T3 drift-detection 8-case matrix.

## Usage

```bash
# Run all tests; first-failure-exit
bash tests/i5-parity.sh

# Run a single test
bash tests/i5-parity.sh --only t0

# Run all T3 cases (drift detection matrix)
bash tests/i5-parity.sh --only t3

# Include the advisory perf test
bash tests/i5-parity.sh --perf
```

```powershell
# PowerShell launcher (Windows, no Git Bash terminal needed)
.\tests\i5-parity.ps1
.\tests\i5-parity.ps1 -Only t0
.\tests\i5-parity.ps1 -Perf
```

## Test groups

| ID | Group | What it asserts |
|----|-------|------------------|
| `t0_syntax` | Static syntax | `bash -n` on every `.sh`; PS parser on every expected `.ps1`. Errors with `MISSING:` if a `.ps1` file is absent — that is the **failing-test FIRST** baseline before I5 ports land. |
| `t1_markers_pre/se/stop` | markers.log byte-equivalence | Per-hook: format `<ISO8601>  <event>  snapshot_id=<TS>  ...`, two-space-separated, ASCII-only, LF-terminated, no UTF-8 BOM. Stop's line omits the `files=` clause per I3.5. |
| `t2_naming_pre/se` | Snapshot file naming | `STATE-<TS>.md`, `journal-<TS>.md`, `next-<TS>.md` for PreCompact; `sessionend-{STATE,journal,next}-<TS>.md` for SessionEnd. |
| `t3_drift_a..h` | Drift detection 8-case matrix | Mirrors I2's verification report. (a) STATE.md missing → exact `[DRIFT] STATE.md missing -- run /bootstrap`. (b) template form. (c) all 4 fields absent. (d–g) field-level skews. (h) all 4 skewed → 4 lines + summary. |
| `t4_bucket_prune` | Stop bucketed prune | 12 stop-*.md files → `prune-snapshots.ps1 stop 10` → exactly 10 retained. |
| `t5_restore` | Stop restore drill | Capture snapshot → corrupt STATE.md → restore from `stop-<TS>.md` → byte-equality. |
| `t6_chrono` | markers.log chronological order | PreCompact + Stop + SessionEnd → `awk -F'  ' '{print $2}' markers.log` returns `precompact / stop / sessionend`. |
| `t7_heredoc_diff` | Bootstrap heredoc byte-equivalence | bash session-start-load.sh + PS port against same fixtures → diff fixed text (after stripping variable git-state lines). PS stdout must NOT contain CR (M3 fix gate). The F12.3 5c paragraph must survive byte-for-byte. |
| `t8_install_select` | Settings.json runtime selection | `node tools/cli.js init` on a Git-Bash-present host → settings.json has cwd-anchored `bash -c 'cd "$CLAUDE_PROJECT_DIR" && exec bash .claude/hooks/<name>.sh'` wiring (v2.2.3+) + config.sh has `CONTROL_HOOK_RUNTIME=bash`. |
| `t9_uninstall` | Uninstall completeness | Mixed-runtime install (sh + ps1 both copied) → uninstall removes all hook files. |
| `t10_doc` | Doc grep | README + PROJECT_PROTOCOL.md prose updated correctly: no `graceful degradation`, no `will not function without bash`, has `CONTROL_HOOK_RUNTIME`, has `quadruplication` contract subsection. |
| `t_perf` | Stop hook perf budget (advisory) | 100 cmp-deduped Stop fires under 5ms mean. Skipped if budget exceeded (advisory only). |

## Failing-test FIRST baseline

When I5 has not landed any port yet, `bash tests/i5-parity.sh --only t0` is expected to **fail** with `MISSING: .claude/hooks/<name>.ps1` for each of the 5 PS hooks. This is the test-driven baseline — Step 0 lands the harness; subsequent steps each cross off a `MISSING:` by landing the corresponding `.ps1` file.
