# agent-codebase-skills

**English** | [简体中文](./README.zh-CN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![AGENTS.md](https://img.shields.io/badge/AGENTS.md-compatible-brightgreen)](https://agents.md)
[![Claude Code](https://img.shields.io/badge/Claude_Code-skills-d97757)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-blue.svg)](https://github.com/Zrzzzz/agent-codebase-skills/pulls)

> Claude Code skills for using AI agents to develop and maintain **large, long-lived codebases** across many sessions.

An agent doesn't stay effective in a codebase by remembering harder. It stays effective when the three kinds of project knowledge — **rules, state, and workflows** — each live in the right place, each with an always-on or on-demand loading path. This repo ships three complementary infrastructure skills that set that up in one command each.

## Quick install

**As a Claude Code plugin** (recommended — inside any Claude Code session):

```text
/plugin marketplace add Zrzzzz/agent-codebase-skills
/plugin install agent-codebase-skills@agent-codebase-skills
```

**Or via the install script** (symlinks into `~/.claude/skills/`, updates with `git pull`):

```bash
curl -fsSL https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/install.sh | bash
```

Pick one — installing both registers the skills twice. Prefer manual steps? See [Manual install](#manual-install).

## The skills

| Skill | Layer | What it installs |
| --- | --- | --- |
| [`init-agents-md`](./init-agents-md/SKILL.md) | **Stable conventions** | Writes the rules that almost never change — architecture, naming, build/test/lint commands, directory boundaries, dependency direction — into `CLAUDE.md` or [`AGENTS.md`](https://agents.md) (the cross-tool open standard), plus nested per-module memory files for monorepos and frontend/backend splits. Four modes: `claude` / `agents` / `both` / `migrate`. |
| [`init-session-notes`](./init-session-notes/SKILL.md) | **Session archive** | Installs a SessionEnd hook: when a session ends, a detached worker runs `claude -p` to distill 3–8 key takeaways into `docs/session-notes.md`; auto-compacts with an LLM once the file exceeds 45 KB. |
| [`init-agent-task-md`](./init-agent-task-md/SKILL.md) | **Task management** (v3 · coordination-free + hook-enforced) | One file per task under `docs/tasks/T-<slug>.md` — **the filename is the ID**, so there is no numbering, no lock, and no main-checkout choreography: any agent in any worktree just creates its file (a slug collision means two agents picked up the same work — a signal, not an error). `docs/TASKS.md` is an index view regenerated automatically by git hooks: `pre-commit` re-indexes and stages it, `post-merge` refreshes after pulls — nobody has to remember to run a script. A mandatory "task entry protocol" block in CLAUDE.md/AGENTS.md routes every user-reported bug or feature request to a `bugfix`/`feat` task + branch *before* code is touched, and the pre-commit hook enforces it (feature branches without a matching task file can't commit; direct commits to `main` are blocked). Status changes are a one-line frontmatter edit — last-touched dates derive from `git log`, so there is no `updated` field to keep in sync. At release time `scripts/tasks-release.sh` appends the entry straight into CHANGELOG's Unreleased section and retires the task file; `--cut <version>` cuts a release. Re-running the skill migrates v1 (monolithic TASKS.md) and v2 (numbered T-XXX) repos automatically. |

The three skills are **fully independent** — install any one alone, or all three for the full stack.

> The fourth layer — **reusable workflows** (`.claude/skills/*`) — is deliberately not initialized by any skill. Those crystallize out of real work (deploy, CI, load-testing, remote DB migrations). Each skill above installs a behavior rule that makes the agent proactively offer to capture such a flow as a skill when it notices one.

## Why layers

Stuffing all project knowledge into one `CLAUDE.md` (or relying on agent memory alone) fails in two well-known ways:

1. **The longer an always-on file gets, the less each rule weighs.** Architecture conventions mixed with task status mixed with yesterday's gotchas means the agent scans 200 lines to find the one rule that applies now.
2. **Lifecycles get tangled.** "Dependencies may only point A → B" holds for years; "backfill the postgres backup tomorrow" is gone in a week. Keep them together and you either hand-edit an always-on file constantly, or your task list is permanently stale.

The layered layout:

```
Stable conventions (years)     → CLAUDE.md / AGENTS.md   ← always-on, hand-written
Volatile state (weeks)         → docs/session-notes.md   ← always-on (@import), appended by hook
                                 docs/TASKS.md           ← always-on (@import), moves with branches/deploys
Reusable workflows (on demand) → .claude/skills/*        ← on-demand, invoked when needed
```

`init-agents-md` installs the first layer; `init-session-notes` + `init-agent-task-md` install the second (session notes and task view respectively); the third grows out of your collaboration with the agent over time.

## See what you get

No install needed to judge it — [`examples/demo-webapp/`](./examples/demo-webapp/) is a snapshot of the exact files the three skills generate for a typical frontend + backend web project: the `AGENTS.md` + thin-shell `CLAUDE.md` pair, a nested `frontend/AGENTS.md`, hook-appended `docs/session-notes.md`, and the file-per-task `docs/tasks/` with its auto-generated `docs/TASKS.md` index.

> Note: the generated templates are currently written in Chinese. English templates are on the [roadmap](#roadmap).

## Manual install

<details>
<summary>Option A — clone + symlink (what install.sh does)</summary>

```bash
git clone https://github.com/Zrzzzz/agent-codebase-skills.git
cd agent-codebase-skills

mkdir -p ~/.claude/skills
ln -s "$PWD/init-agents-md"      ~/.claude/skills/init-agents-md
ln -s "$PWD/init-session-notes"  ~/.claude/skills/init-session-notes
ln -s "$PWD/init-agent-task-md"  ~/.claude/skills/init-agent-task-md
```

A later `git pull` updates all skills in place.

</details>

<details>
<summary>Option B — copy just the SKILL.md files</summary>

```bash
mkdir -p ~/.claude/skills/init-agents-md ~/.claude/skills/init-session-notes ~/.claude/skills/init-agent-task-md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-agents-md/SKILL.md      -o ~/.claude/skills/init-agents-md/SKILL.md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-session-notes/SKILL.md  -o ~/.claude/skills/init-session-notes/SKILL.md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-agent-task-md/SKILL.md  -o ~/.claude/skills/init-agent-task-md/SKILL.md
```

</details>

**Verify**: in any Claude Code session, type `/` — you should see `init-agents-md`, `init-session-notes`, and `init-agent-task-md` in the candidate list.

## Usage

From the root of the project you want to set up, inside Claude Code:

```text
/init-agents-md       # write CLAUDE.md / AGENTS.md layered conventions (+ nested per-module memory)
/init-session-notes   # install the SessionEnd hook + initialize docs/session-notes.md
/init-agent-task-md   # initialize docs/tasks/ + TASKS.md index + CHANGELOG.md (+ optional session-end automation)
```

All skills are **idempotent** — re-running replaces only the skill-managed sentinel blocks and never touches content you wrote by hand. Safe to run on existing projects and to re-run after upgrades.

## Compatibility

- Requires: [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI, `jq`, `perl`, `bash`.
- The `AGENTS.md` generated by `init-agents-md` follows the [agents.md](https://agents.md) open standard, read natively by Codex, Cursor, Copilot, Gemini CLI, Aider, Windsurf, Zed, and 20+ other tools.
- The SessionEnd hook from `init-session-notes` is a Claude Code-specific mechanism (other tools won't trigger it), and the optional task auto-detection from `init-agent-task-md` rides on that hook. The generated `TASKS.md` / `CHANGELOG.md` themselves are plain markdown and tool-agnostic.

## Roadmap

- [ ] English versions of the generated templates (memory files, task files, hook prompts)
- [x] Package as a Claude Code plugin for one-command `/plugin install`
- [ ] Terminal GIF demos (vhs) of each skill run

## License

[MIT](./LICENSE)
