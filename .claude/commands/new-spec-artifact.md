---
description: (DEPRECATED v2.0; alias for /spec-amend) Append a dated amendment to .control/SPEC.md
argument-hint: <slug>
---

> **Deprecated in v2.0; removal scheduled for v2.1.** This command was renamed to `/spec-amend` because v2.0 collapsed the v1.3 spec layout (separate `.control/spec/artifacts/<date>.md` files) into a single `.control/SPEC.md` with an `## Artifacts (chronological)` section. The "artifact" terminology no longer reflects the file structure.
>
> **Use `/spec-amend $ARGUMENTS` instead.** Behavior is identical.

This file is kept for one minor version of grace so operators with the old name in muscle memory don't hit a "command not found" error mid-session. The alias forwards directly to the spec-amend logic.

Follow `.claude/commands/spec-amend.md` exactly with the same `$ARGUMENTS` slug.
