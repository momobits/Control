#!/usr/bin/env node

// control-workflow CLI -- Node port of setup.sh / setup.ps1 / uninstall.sh / uninstall.ps1.
// Zero npm dependencies; pure Node built-ins (fs, path, child_process, readline).
//
// Commands:
//   init [target-dir] [--force]    Install Control into a project
//   upgrade [target-dir]           Refresh framework files (preserves project content)
//   uninstall [target-dir] [--force]  Remove Control framework
//   version | -v | --version
//   help    | -h | --help

const fs = require("fs");
const path = require("path");
const { execSync, spawnSync } = require("child_process");
const readline = require("readline");

const PKG_ROOT = path.resolve(__dirname, "..");
const VERSION = fs.readFileSync(path.join(PKG_ROOT, "VERSION"), "utf8").trim();

// === I/O helpers ===

function say(msg)  { console.log(`[control-setup] ${msg}`); }
function warn(msg) { console.error(`[control-setup] WARNING: ${msg}`); }
function die(msg)  { console.error(`[control-setup] ERROR: ${msg}`); process.exit(1); }

function prompt(question) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    return new Promise(resolve => {
        rl.question(question, answer => {
            rl.close();
            resolve(answer);
        });
    });
}

// === File ops ===

function copyFile(src, dst, kind, opts) {
    // kind: 'framework' (refresh on --upgrade) or 'project' (preserve unless --force)
    const dstDir = path.dirname(dst);
    if (dstDir && !fs.existsSync(dstDir)) fs.mkdirSync(dstDir, { recursive: true });

    if (!fs.existsSync(dst)) {
        fs.copyFileSync(src, dst);
        say(`  + ${dst}`);
        return;
    }
    if (kind === "framework") {
        if (opts.upgrade || opts.force) {
            fs.copyFileSync(src, dst);
            say(`  ~ ${dst} (updated)`);
        } else {
            say(`  = ${dst} (exists -- use upgrade to update)`);
        }
    } else if (kind === "project") {
        if (opts.force) {
            fs.copyFileSync(src, dst);
            say(`  ~ ${dst} (forced)`);
        } else {
            say(`  = ${dst} (exists -- kept; --force to overwrite)`);
        }
    } else {
        die(`copyFile: unknown kind '${kind}'`);
    }
}

function listFiles(dir, ext) {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter(f => !ext || f.endsWith(ext)).map(f => path.join(dir, f));
}

function chmodExec(p) {
    try { fs.chmodSync(p, 0o755); } catch (_) { /* Windows: chmod is a no-op */ }
}

// === Git wrappers ===

function gitOK(args) {
    return spawnSync("git", args, { stdio: "pipe" }).status === 0;
}
function gitCapture(args) {
    const r = spawnSync("git", args, { stdio: "pipe", encoding: "utf8" });
    return r.status === 0 ? (r.stdout || "").trim() : "";
}
function gitRun(args) {
    const r = spawnSync("git", args, { stdio: "inherit" });
    if (r.status !== 0) die(`git ${args.join(" ")} failed (exit ${r.status})`);
}
function gitQuiet(args) {
    spawnSync("git", args, { stdio: "pipe" });
}

function bashAvailable() {
    try {
        const r = spawnSync("bash", ["-c", "exit 0"], { stdio: "pipe" });
        return r.status === 0;
    } catch (_) {
        return false;
    }
}

// === init / upgrade ===

async function init(targetDirArg, opts) {
    if (!fs.existsSync(path.join(PKG_ROOT, ".claude"))) {
        die(`framework source not found at ${PKG_ROOT} -- reinstall the npm package`);
    }
    const target = path.resolve(targetDirArg);
    if (!fs.existsSync(target)) die(`target directory does not exist: ${target}`);

    // Refuse to install into the package source directory (would pollute the source tree).
    if (path.resolve(target) === PKG_ROOT) {
        die(`target resolves to the package source directory (${PKG_ROOT}). Use a different target.`);
    }

    if (!gitOK(["--version"])) die("git is required. Install git and retry.");

    say(`Installing Control v${VERSION} into ${target}`);
    if (opts.upgrade) say("(upgrade mode -- framework files only, project content untouched)");

    process.chdir(target);

    // git init if missing
    if (!fs.existsSync(".git")) {
        say("Initialising git repository");
        gitRun(["init", "--quiet"]);
    }

    // .control/ framework area
    say("Installing .control/");
    fs.mkdirSync(".control/snapshots", { recursive: true });
    copyFile(path.join(PKG_ROOT, ".control/VERSION"),   ".control/VERSION",   "framework", opts);
    copyFile(path.join(PKG_ROOT, ".control/config.sh"), ".control/config.sh", "project",   opts);
    if (!fs.existsSync(".control/snapshots/.gitkeep")) fs.writeFileSync(".control/snapshots/.gitkeep", "");

    // .claude/ commands + hooks (settings.json is generated below from detected runtime)
    say("Installing .claude/settings.json, commands, hooks");
    for (const f of listFiles(path.join(PKG_ROOT, ".claude/commands"), ".md")) {
        copyFile(f, `.claude/commands/${path.basename(f)}`, "framework", opts);
    }
    for (const f of listFiles(path.join(PKG_ROOT, ".claude/hooks"), ".sh")) {
        const dst = `.claude/hooks/${path.basename(f)}`;
        copyFile(f, dst, "framework", opts);
        chmodExec(dst);
    }
    // PowerShell ports also installed (always both shipped; runtime selection below).
    for (const f of listFiles(path.join(PKG_ROOT, ".claude/hooks"), ".ps1")) {
        copyFile(f, `.claude/hooks/${path.basename(f)}`, "framework", opts);
    }

    // .githooks/ (git-side; commit-msg shape enforcement)
    if (fs.existsSync(path.join(PKG_ROOT, ".githooks"))) {
        say("Installing .githooks/");
        for (const name of fs.readdirSync(path.join(PKG_ROOT, ".githooks"))) {
            const src = path.join(PKG_ROOT, ".githooks", name);
            if (!fs.statSync(src).isFile()) continue;
            const dst = `.githooks/${name}`;
            copyFile(src, dst, "framework", opts);
            chmodExec(dst);
        }
    }

    // .control/ managed content (project files first run, framework on upgrade)
    if (opts.upgrade) {
        say("Upgrade mode: refreshing .control/templates/ and .control/runbooks/ only");
        for (const f of listFiles(path.join(PKG_ROOT, ".control/templates"), ".md")) {
            copyFile(f, `.control/templates/${path.basename(f)}`, "framework", opts);
        }
        for (const f of listFiles(path.join(PKG_ROOT, ".control/runbooks"), ".md")) {
            copyFile(f, `.control/runbooks/${path.basename(f)}`, "framework", opts);
        }
    } else {
        say("Installing .control/ managed content");
        for (const d of [
            ".control/architecture/decisions", ".control/architecture/interfaces",
            ".control/phases", ".control/progress",
            ".control/issues/OPEN", ".control/issues/RESOLVED",
            ".control/runbooks", ".control/templates",
        ]) {
            fs.mkdirSync(d, { recursive: true });
        }

        copyFile(path.join(PKG_ROOT, ".control/progress/STATE.md"),          ".control/progress/STATE.md",          "project", opts);
        copyFile(path.join(PKG_ROOT, ".control/progress/journal.md"),        ".control/progress/journal.md",        "project", opts);
        copyFile(path.join(PKG_ROOT, ".control/progress/next.md"),           ".control/progress/next.md",           "project", opts);
        copyFile(path.join(PKG_ROOT, ".control/architecture/phase-plan.md"), ".control/architecture/phase-plan.md", "project", opts);

        for (const f of listFiles(path.join(PKG_ROOT, ".control/runbooks"), ".md")) {
            copyFile(f, `.control/runbooks/${path.basename(f)}`, "framework", opts);
        }
        for (const f of listFiles(path.join(PKG_ROOT, ".control/templates"), ".md")) {
            copyFile(f, `.control/templates/${path.basename(f)}`, "framework", opts);
        }

        copyFile(path.join(PKG_ROOT, ".control/SPEC.md"), ".control/SPEC.md", "project", opts);

        for (const gk of [
            ".control/architecture/decisions/.gitkeep",
            ".control/issues/OPEN/.gitkeep",
            ".control/issues/RESOLVED/.gitkeep",
            ".control/phases/.gitkeep",
        ]) {
            if (!fs.existsSync(gk)) fs.writeFileSync(gk, "");
        }
    }

    // v1.3 -> v2.0 spec layout migration (UPGRADE only).
    // Detects the legacy 3-location spec layout (.control/spec/SPEC.md +
    // spec/artifacts/ + architecture/overview.md) and offers to consolidate
    // into the new single .control/SPEC.md. See README.md "Migration from v1.3".
    if (opts.upgrade && !fs.existsSync(".control/SPEC.md") &&
        (fs.existsSync(".control/spec") || fs.existsSync(".control/architecture/overview.md"))) {
        if (process.stdin.isTTY) {
            const ans = await prompt("v1.3 spec layout detected. Migrate to v2.0 single-file layout? [y/N] ");
            if (/^(y|Y|yes|YES)$/.test(ans)) {
                say("Migrating spec layout...");
                const today = new Date().toISOString().slice(0, 10);
                let body = "# Project Spec\n\n";
                body += `> Migrated from v1.3 layout on ${today}. See README.md "Migration from v1.3" for context.\n\n`;
                if (fs.existsSync(".control/architecture/overview.md")) {
                    body += "---\n\n## Overview (migrated from .control/architecture/overview.md)\n\n";
                    body += fs.readFileSync(".control/architecture/overview.md", "utf8") + "\n";
                }
                if (fs.existsSync(".control/spec/SPEC.md")) {
                    body += "---\n\n## Spec (migrated from .control/spec/SPEC.md)\n\n";
                    body += fs.readFileSync(".control/spec/SPEC.md", "utf8") + "\n";
                }
                if (fs.existsSync(".control/spec/artifacts")) {
                    body += "---\n\n## Artifacts (chronological, migrated from .control/spec/artifacts/)\n\n";
                    for (const af of fs.readdirSync(".control/spec/artifacts")) {
                        if (!af.endsWith(".md")) continue;
                        body += `### ${af.replace(/\.md$/, "")}\n\n`;
                        body += fs.readFileSync(path.join(".control/spec/artifacts", af), "utf8") + "\n";
                    }
                }
                fs.writeFileSync(".control/SPEC.md", body);
                fs.mkdirSync(".control.v1.3-backup", { recursive: true });
                if (fs.existsSync(".control/spec")) fs.renameSync(".control/spec", ".control.v1.3-backup/spec");
                if (fs.existsSync(".control/architecture/overview.md")) fs.renameSync(".control/architecture/overview.md", ".control.v1.3-backup/overview.md");
                say("Migrated to .control/SPEC.md. Old files backed up to .control.v1.3-backup/.");
                say("Review the merge, commit, then delete .control.v1.3-backup/ when satisfied.");
            } else {
                say("Spec migration deferred. Re-run upgrade to retry, or migrate manually.");
            }
        } else {
            warn("v1.3 spec layout detected but UPGRADE is non-interactive. Skipping migration.");
            warn("Re-run interactively, or migrate manually per README.md \"Migration from v1.3\".");
        }
    }

    // CLAUDE.md, .control/PROJECT_PROTOCOL.md
    copyFile(path.join(PKG_ROOT, "CLAUDE.md"), "CLAUDE.md", "project", opts);
    if (fs.existsSync(path.join(PKG_ROOT, ".control/PROJECT_PROTOCOL.md"))) {
        copyFile(path.join(PKG_ROOT, ".control/PROJECT_PROTOCOL.md"), ".control/PROJECT_PROTOCOL.md", "framework", opts);
    }

    // .gitignore (Control block)
    const giMarker = "# --- Control framework ---";
    if (!fs.existsSync(".gitignore") || !fs.readFileSync(".gitignore", "utf8").includes(giMarker)) {
        say("Updating .gitignore");
        const block = `\n${giMarker}\n.control/snapshots/\n.control/.is-source-repo\n.claude/settings.local.json\n# --- /Control ---\n`;
        fs.appendFileSync(".gitignore", block);
    }

    // Source-repo sentinel (interactive only, fresh install only).
    if (!opts.upgrade && process.stdin.isTTY && !fs.existsSync(".control/.is-source-repo")) {
        const ans = await prompt("Is this the Control source/dev repo (NOT a project using Control)? [y/N] ");
        if (/^(y|Y|yes|YES)$/.test(ans)) {
            const sentinel = "# Control source/dev repo sentinel\n# Created by control-workflow init on operator confirmation.\n# Suppresses SessionStart hook's drift detection so the shipped-as-template\n# STATE.md doesn't trigger state-md-template drift every session.\nCONTROL_SOURCE_REPO=true\n";
            fs.writeFileSync(".control/.is-source-repo", sentinel);
            say("Created .control/.is-source-repo (drift detection will skip on this repo)");
        }
    }

    // Initial commit + tag
    if (opts.upgrade) {
        say("Upgrade complete. Review changes with 'git status' and commit when ready.");
    } else {
        const headExists = gitOK(["rev-parse", "--verify", "HEAD"]);
        if (headExists) {
            const porcelain = gitCapture(["status", "--porcelain"]);
            if (porcelain) {
                gitQuiet(["add", "-A"]);
                gitQuiet(["commit", "--quiet", "-m", `chore(install): install Control framework v${VERSION}`]);
                say(`Committed: install Control framework v${VERSION}`);
            }
        } else {
            gitQuiet(["add", "-A"]);
            gitQuiet(["commit", "--quiet", "-m", `chore(install): scaffold project with Control framework v${VERSION}`]);
            say("Initial commit created");
        }
        if (!gitOK(["rev-parse", "--verify", "protocol-initialised"])) {
            gitQuiet(["tag", "protocol-initialised"]);
            say("Tagged: protocol-initialised");
        }
    }

    // Hook runtime detection + settings.json + config record
    const bashOk = bashAvailable();
    let existingRuntime = "";
    if (fs.existsSync(".control/config.sh")) {
        const m = fs.readFileSync(".control/config.sh", "utf8").match(/^CONTROL_HOOK_RUNTIME=(.+)$/m);
        if (m) existingRuntime = m[1].trim();
    }
    const runtime = (opts.upgrade && existingRuntime) ? existingRuntime : (bashOk ? "bash" : "powershell");
    say(`Hook runtime: ${runtime}`);

    // Anchor each hook command to the project root via $CLAUDE_PROJECT_DIR
    // (set by Claude Code per https://code.claude.com/docs/en/hooks.md).
    // Without this, hooks fail with "No such file or directory" whenever a
    // prior Bash tool call drifted cwd into a subdir of the project.
    const cmdFor = (name) => runtime === "powershell"
        ? `powershell -NoProfile -Command "Set-Location -LiteralPath $env:CLAUDE_PROJECT_DIR; & .claude\\hooks\\${name}.ps1"`
        : `bash -c 'cd "$CLAUDE_PROJECT_DIR" && exec bash .claude/hooks/${name}.sh'`;
    const hookEntry = (name) => ({
        matcher: "",
        hooks: [{ type: "command", command: cmdFor(name) }],
    });
    const settingsObj = {
        hooks: {
            PreCompact: [hookEntry("pre-compact-dump")],
            SessionStart: [hookEntry("session-start-load")],
            SessionEnd: [hookEntry("session-end-commit")],
            Stop: [hookEntry("stop-snapshot")],
        },
    };
    const settings = JSON.stringify(settingsObj, null, 2) + "\n";
    fs.writeFileSync(".claude/settings.json", settings);
    say(`Wrote .claude/settings.json (hook runtime: ${runtime})`);

    if (!opts.upgrade && !existingRuntime && fs.existsSync(".control/config.sh")) {
        fs.appendFileSync(".control/config.sh", `\nCONTROL_HOOK_RUNTIME=${runtime}\n`);
        say(`Recorded CONTROL_HOOK_RUNTIME=${runtime} in .control/config.sh`);
    }

    // Wire core.hooksPath (skip if already set; preserves husky / pre-commit)
    if (!opts.upgrade && fs.existsSync(".githooks/commit-msg")) {
        const existing = gitCapture(["config", "--local", "--get", "core.hooksPath"]);
        if (!existing) {
            gitQuiet(["config", "--local", "core.hooksPath", ".githooks"]);
            say("Wired commit-msg hook (core.hooksPath = .githooks)");
        } else if (existing === ".githooks") {
            say("core.hooksPath already set to .githooks -- commit-msg hook active");
        } else {
            warn(`core.hooksPath is already set to '${existing}' (likely husky / pre-commit / lefthook).`);
            warn("Control's commit-msg hook NOT auto-wired. To enable: chain '.githooks/commit-msg' from your existing hooksPath dir, OR unset and rerun init.");
        }
    }

    // Done message
    console.log(`
Control v${VERSION} installed at ${target}

Layout:
  CLAUDE.md                          -- auto-loaded every session
  .control/PROJECT_PROTOCOL.md       -- framework reference
  .control/                          -- all Control-managed files
    config.sh, VERSION, snapshots/
    progress/ architecture/ phases/ issues/ runbooks/ templates/ SPEC.md
  .claude/                           -- commands, hooks, settings
  docs/                              -- UNTOUCHED (your project's own docs live here)

Next steps:
  1. If you have a spec file: /bootstrap <path-to-spec>
     If you don't: /bootstrap (no args -- scans the codebase and prompts you)
  2. Review the bootstrap output
  3. Commit
  4. /session-start

Run 'npx control-workflow upgrade' to update framework files without touching your project content.

Hook runtime: ${runtime} (set CONTROL_HOOK_RUNTIME in .control/config.sh and rerun init to switch).
Both .sh and .ps1 hooks ship; .claude/settings.json is wired to the chosen runtime.
`);
}

// === uninstall ===

const COMMAND_FILES_TO_REMOVE = [
    ".claude/commands/bootstrap.md",
    ".claude/commands/control-next.md",        // legacy alias (cleanup of v2.0 installs)
    ".claude/commands/session-start.md",
    ".claude/commands/session-end.md",
    ".claude/commands/work-next.md",
    ".claude/commands/new-issue.md",
    ".claude/commands/close-issue.md",
    ".claude/commands/new-adr.md",
    ".claude/commands/new-spec-artifact.md",   // legacy alias (cleanup of v2.0 installs)
    ".claude/commands/spec-amend.md",
    ".claude/commands/phase-close.md",
    ".claude/commands/validate.md",
];

const HOOK_FILES_TO_REMOVE = [
    ".claude/hooks/pre-compact-dump.sh",
    ".claude/hooks/session-start-load.sh",
    ".claude/hooks/session-end-commit.sh",
    ".claude/hooks/stop-snapshot.sh",
    ".claude/hooks/prune-snapshots.sh",
    ".claude/hooks/regenerate-next-md.sh",
    ".claude/hooks/pre-compact-dump.ps1",
    ".claude/hooks/session-start-load.ps1",
    ".claude/hooks/session-end-commit.ps1",
    ".claude/hooks/stop-snapshot.ps1",
    ".claude/hooks/prune-snapshots.ps1",
    ".claude/hooks/regenerate-next-md.ps1",
];

async function uninstall(targetDirArg, opts) {
    const target = path.resolve(targetDirArg);
    if (!fs.existsSync(target)) die(`target directory does not exist: ${target}`);
    if (!fs.existsSync(path.join(target, ".control"))) {
        say(`No Control install detected at ${target}`);
        return;
    }

    console.log(`This will remove the Control framework from:
  ${target}

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
`);

    if (!opts.force) {
        if (!process.stdin.isTTY) die("Non-interactive run with no --force flag. Aborting.");
        const ans = await prompt("Proceed? [y/N] ");
        if (!/^(y|Y|yes|YES)$/.test(ans)) {
            say("Aborted.");
            process.exit(1);
        }
    }

    process.chdir(target);

    fs.rmSync(".control", { recursive: true, force: true });

    for (const f of [".claude/settings.json", ...HOOK_FILES_TO_REMOVE, ...COMMAND_FILES_TO_REMOVE]) {
        try { fs.unlinkSync(f); } catch (_) {}
    }

    for (const d of [".claude/commands", ".claude/hooks", ".claude"]) {
        try {
            if (fs.readdirSync(d).length === 0) fs.rmdirSync(d);
        } catch (_) {}
    }

    // .githooks/commit-msg -- only if Control's marker is present
    if (fs.existsSync(".githooks/commit-msg") &&
        fs.readFileSync(".githooks/commit-msg", "utf8").includes("control:commit-msg")) {
        try { fs.unlinkSync(".githooks/commit-msg"); } catch (_) {}
        try {
            if (fs.readdirSync(".githooks").length === 0) fs.rmdirSync(".githooks");
        } catch (_) {}
    }

    // Revert core.hooksPath if Control set it
    const hooksPath = gitCapture(["config", "--local", "--get", "core.hooksPath"]);
    if (hooksPath === ".githooks") {
        gitQuiet(["config", "--local", "--unset", "core.hooksPath"]);
        say("Unset core.hooksPath (was .githooks -- set by Control)");
    }

    // Root-level framework files
    try { fs.unlinkSync("PROJECT_PROTOCOL.md"); } catch (_) {}

    if (fs.existsSync("CLAUDE.md") &&
        fs.readFileSync("CLAUDE.md", "utf8").includes("<!-- control:managed -->")) {
        try { fs.unlinkSync("CLAUDE.md"); say("Removed CLAUDE.md (bore the <!-- control:managed --> marker)"); } catch (_) {}
    } else if (fs.existsSync("CLAUDE.md")) {
        say("CLAUDE.md kept (no <!-- control:managed --> marker found -- edit out manually if you want it removed)");
    }

    // Strip Control block from .gitignore
    if (fs.existsSync(".gitignore")) {
        const content = fs.readFileSync(".gitignore", "utf8");
        if (content.includes("# --- Control framework ---")) {
            const out = [];
            let inBlock = false;
            for (const line of content.split("\n")) {
                if (/^# --- Control framework ---/.test(line)) { inBlock = true; continue; }
                if (inBlock && /^# --- \/Control ---/.test(line)) { inBlock = false; continue; }
                if (!inBlock) out.push(line);
            }
            fs.writeFileSync(".gitignore", out.join("\n"));
            say("Cleaned .gitignore");
        }
    }

    say("Control uninstalled. Commit the removal when ready: git commit -am 'chore: remove Control framework'");
}

// === help / version ===

function showHelp() {
    console.log(`
  control-workflow v${VERSION}
  Phased session-management framework for Claude Code

  Usage:
    npx control-workflow init [target-dir] [--force]      Install Control into a project
    npx control-workflow upgrade [target-dir]             Refresh framework files (preserves project content)
    npx control-workflow uninstall [target-dir] [--force] Remove Control framework
    npx control-workflow version                          Show version
    npx control-workflow help                             Show this help

  After install:
    1. Open Claude Code in your project
    2. Run /bootstrap to derive project-specific content from a spec
    3. Run /session-start to begin work

  See https://github.com/momobits/Control for full documentation.
`);
}

// === Main ===

(async () => {
    const args = process.argv.slice(2);
    const command = args[0] || "help";

    let targetDir = process.cwd();
    const opts = {};
    for (let i = 1; i < args.length; i++) {
        if (args[i] === "--force" || args[i] === "-f") opts.force = true;
        else if (args[i] === "--upgrade") opts.upgrade = true;
        else if (!args[i].startsWith("-")) targetDir = args[i];
    }

    switch (command) {
        case "init":
            await init(targetDir, opts);
            break;
        case "upgrade":
            opts.upgrade = true;
            await init(targetDir, opts);
            break;
        case "uninstall":
        case "remove":
            await uninstall(targetDir, opts);
            break;
        case "version":
        case "--version":
        case "-v":
            console.log(VERSION);
            break;
        case "help":
        case "--help":
        case "-h":
            showHelp();
            break;
        default:
            console.error(`\n  Unknown command: ${command}\n`);
            showHelp();
            process.exit(1);
    }
})().catch(err => {
    console.error(`\n  Error: ${err.message}\n`);
    process.exit(1);
});
