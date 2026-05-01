---
description: (DEPRECATED v2.0; alias) Read-only "what next?" recommendation - use /session-start instead
---

> **Deprecated in v2.0; removal scheduled for v2.1.** The priority decision tree this command housed was extracted to `.control/runbooks/work-priority.md` and absorbed into `/session-start` (which is now idempotent — re-running mid-session re-prints status + recommendation).
>
> **Use `/session-start` instead.** Same recommendation, plus the canonical status block and drift handling.
>
> Keeping this alias for one minor version of grace so operators with `/control-next` in muscle memory don't hit a "command not found" mid-session.

## Behavior in v2.0

When invoked, follow the work-priority decision tree from `.control/runbooks/work-priority.md` against current state and emit a single-line recommendation. Read-only — recommends, does not execute.

Argument variants (preserved from v1.4 for muscle memory):
- `/control-next` — one recommended command + one-line justification
- `/control-next --why` — also print observed state inputs (audit trail)
- `/control-next --all` — list all plausible next commands when multiple fit

See `.control/runbooks/work-priority.md` for:
- Full state-input list (which files / git commands to read)
- Priority 0–6 decision tree
- Ignorable-dirty rule
- `[HALT]` marker convention in steps.md
- `--why` audit summary format
- `--all` multi-path enumeration cases
- Limitations

## Migration to /session-start

`/session-start` (v2.0+) does everything this command did, plus:
- Reads STATE.md and current phase docs
- Surfaces `[control:state]` / `[control:drift]` / `[control:validate]` from the SessionStart hook (or does the equivalent manual check)
- Emits the canonical narrative status block
- Then applies the same work-priority tree to recommend next action
- Idempotent: safe to re-run mid-session if you just want the "what next?" probe

Replace `/control-next` with `/session-start` in your scripts and notes.
