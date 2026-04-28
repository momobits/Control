#!/usr/bin/env bash
# Control hook: SessionStart
# Fires at the beginning of every Claude Code session.
# Injects the session-start protocol into context so Claude bootstraps automatically.

set -euo pipefail

LATEST_SNAP=$(ls -t .control/snapshots/STATE-*.md 2>/dev/null | head -1 || echo "")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "not-a-git-repo")

if git rev-parse HEAD >/dev/null 2>&1; then
    GIT_LAST=$(git log -1 --oneline 2>/dev/null)
    if git diff-index --quiet HEAD -- 2>/dev/null && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
        GIT_DIRTY="clean"
    else
        GIT_DIRTY="DIRTY"
    fi
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
else
    GIT_LAST="(no commits yet)"
    GIT_DIRTY="n/a (no HEAD)"
    LAST_TAG="none"
fi

# --- Drift detection (Issue I2) ---------------------------------------------
# Mechanical compare against STATE.md. Emits [DRIFT] lines BEFORE the heredoc
# so they appear at the top of the bootstrap message (Claude attends most
# strongly to the top). Exit 0 always -- drift is a signal, not a hook failure.
STATE_FILE=".control/progress/STATE.md"
DRIFT_LINES=""

extract_field() {
    # Pull the first line matching `- **<label>:**`, strip the prefix, trim CR.
    # Returns empty if the field is absent. Tolerant under set -euo pipefail.
    grep -m1 -E "^- \*\*${1}:\*\*" "$STATE_FILE" 2>/dev/null \
        | sed -E "s/^- \*\*${1}:\*\* *//" \
        | tr -d '\r' \
        || true
}

if [ ! -f "$STATE_FILE" ]; then
    DRIFT_LINES="[DRIFT] STATE.md missing -- run /bootstrap"
elif grep -qE '<short-sha>|<YYYY-MM-DD>|<sha>' "$STATE_FILE"; then
    DRIFT_LINES="[DRIFT] STATE.md is in template form -- run /bootstrap"
else
    STATE_BRANCH=$(extract_field "Branch")
    STATE_LAST_COMMIT=$(extract_field "Last commit")
    STATE_UNCOMMITTED=$(extract_field "Uncommitted changes")
    STATE_LAST_TAG_RAW=$(extract_field "Last phase tag")

    if [ -z "$STATE_BRANCH" ] && [ -z "$STATE_LAST_COMMIT" ] && [ -z "$STATE_UNCOMMITTED" ] && [ -z "$STATE_LAST_TAG_RAW" ]; then
        # All four parser-contract fields absent: schema rename or section deletion.
        DRIFT_LINES="[DRIFT] STATE.md Git state section unparseable (parser-contract fields absent) -- run /validate"
    else
        STATE_LAST_TAG=$(echo "$STATE_LAST_TAG_RAW" | sed -E 's/`//g' | cut -d' ' -f1)
        GIT_LAST_SHA=$(echo "$GIT_LAST" | cut -d' ' -f1)

        if [ -n "$STATE_BRANCH" ] && [ "$STATE_BRANCH" != "$GIT_BRANCH" ]; then
            DRIFT_LINES="${DRIFT_LINES}[DRIFT] STATE.md says branch=${STATE_BRANCH}, actual=${GIT_BRANCH}"$'\n'
        fi
        if [ -n "$STATE_LAST_COMMIT" ] && [ -n "$GIT_LAST_SHA" ] && ! echo "$STATE_LAST_COMMIT" | grep -qF "$GIT_LAST_SHA"; then
            DRIFT_LINES="${DRIFT_LINES}[DRIFT] STATE.md says last commit=\"${STATE_LAST_COMMIT}\", actual=${GIT_LAST}"$'\n'
        fi
        if [ "$STATE_UNCOMMITTED" = "none" ] && [ "$GIT_DIRTY" != "clean" ]; then
            # Special-case: literal `none` <-> tree clean; any other value is operator-described.
            DRIFT_LINES="${DRIFT_LINES}[DRIFT] STATE.md says uncommitted=none, actual=${GIT_DIRTY}"$'\n'
        fi
        if [ -n "$STATE_LAST_TAG" ] && [ "$STATE_LAST_TAG" != "$LAST_TAG" ]; then
            DRIFT_LINES="${DRIFT_LINES}[DRIFT] STATE.md says last tag=${STATE_LAST_TAG}, actual=${LAST_TAG}"$'\n'
        fi
        if [ -n "$DRIFT_LINES" ]; then
            DRIFT_LINES="${DRIFT_LINES}[DRIFT] Verify and update STATE.md before proceeding."
        fi
    fi
fi

if [ -n "$DRIFT_LINES" ]; then
    printf '%s\n\n' "$DRIFT_LINES"
fi
# --- End drift detection ---------------------------------------------------

cat <<EOF
[control:SessionStart] Bootstrap

Before accepting user input, run the session-start protocol:

1. Read .control/progress/STATE.md
2. Read .control/progress/next.md (last session's handoff, if present)
3. Read the current phase README + steps (path in STATE.md)
4. List .control/issues/OPEN/ and flag current-phase blockers

Git state at session start (verify against STATE.md's Git state section):
  branch: $GIT_BRANCH
  last: $GIT_LAST
  working tree: $GIT_DIRTY
  last tag: $LAST_TAG

Latest PreCompact snapshot: ${LATEST_SNAP:-none}

After reading, report the standard status block and wait for the user's go
before editing any code. If [DRIFT] lines were emitted above, surface them
in the status block under \`Git sync:\` and pause for operator reconciliation
before reporting -- do not silently proceed.

After emitting the status block (and before waiting for the user's go to
begin code edits), read .claude/commands/control-next.md, apply its
priority decision tree against current state, and emit "Recommended
next: <command>" as a follow-up line. Skip silently if
.claude/commands/control-next.md does not exist, or if a design-decision
expansion already fired this turn (Step 5b takes precedence over Step 5c).
EOF
