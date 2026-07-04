# Contributing

Thanks for your interest! This repo collects Claude Code skills for long-lived-codebase agent workflows. Contributions of all sizes are welcome — typo fixes, template improvements, new skills.

中文：欢迎任何规模的贡献——错别字、模板改进、新 skill 都可以。Issue / PR 用中文或英文均可。

## Ground rules

- **One skill = one directory** at the repo root, containing a single `SKILL.md` with YAML frontmatter (`name`, `version`, `description`, `license`, `compatibility`, `allowed-tools`). Look at [`init-agents-md/SKILL.md`](./init-agents-md/SKILL.md) for the reference shape.
- **Skills must be idempotent.** Re-running a skill must only replace its own sentinel-marked blocks and never touch content the user wrote by hand. Version-gate upgrades where formats change (see `init-agent-task-md`'s `skill-managed:` version detection).
- **Skills must stay in their lane.** Each skill owns exactly one layer (conventions / session archive / task management). If your change makes one skill reach into another's files, it probably belongs in the other skill — cross-link instead.
- **Embedded scripts must be safe to re-run** and must pass `bash -n`. If you change a generated script (e.g. `tasks-index.sh`), also update the snapshot under [`examples/demo-webapp/`](./examples/demo-webapp/) by actually running the new script on it — don't hand-edit the generated sections.
- **Never use `rm` in skill instructions or generated scripts** — instruct `trash` and keep backups (`cp` before rewrite). This is a hard rule across the repo.

## Submitting changes

1. Fork, create a branch, make your change.
2. If you touched a SKILL.md, bump its `version` (semver: template-content changes = minor, breaking format changes = major) and note the change in your PR description.
3. Open a PR with a [Conventional Commits](https://www.conventionalcommits.org/) style title, e.g. `feat(init-agents-md): ...` or `docs: ...`.

## Proposing a new skill

Open an issue first (use the *Skill proposal* template) describing: which layer/lifecycle of project knowledge it manages, why existing skills can't cover it, and what files it generates. This avoids building something that overlaps an existing skill's lane.
