<!-- init-agents-md:begin v1 -->
## 协作约定（由 init-agents-md 维护）

本仓库使用跨工具开放标准 [AGENTS.md](https://agents.md) 作为稳定约定层，被 Claude Code / Codex / Cursor / Copilot / Gemini CLI / Aider 等工具原生读取。

本项目采用「**约定 / 状态 / 流程**」三层分层：

| 层 | 文件 | 由谁维护 |
| --- | --- | --- |
| 稳定约定 | 本文件 `AGENTS.md` | 人手工编辑（架构、命名、build/test 命令、目录边界、依赖方向） |
| 易变状态 | `docs/session-notes.md` `docs/TASKS.md` | SessionEnd hook（仅 Claude Code 触发，需另跑 `/init-session-notes` 安装）+ 人工裁剪 |
| 可复用流程 | `.claude/skills/*`（Claude Code）/ `.cursor/rules/*.mdc`（Cursor）/ 各工具对应位置 | 重复/环境相关流程沉淀，按需调起 |

会话开始时，agent 应主动读取一次：

- `docs/session-notes.md` — 历次决策与踩坑沉淀
- `docs/TASKS.md` — 当前进行中/待办任务

### 写本文件的纪律
- 只放**几乎不变**的全局规则；任务进度、决策日志、踩坑记录留在 session-notes / TASKS。
- 保持精简。always-on 文件过长会稀释单条规则权重、抬高 agent 探索成本。
- 子目录可放各自的 `AGENTS.md`（如 `frontend/AGENTS.md` `backend/AGENTS.md`），按目录最近优先生效。

### 分支纪律（agent 行为规则）

开新分支**必须用 `git worktree` 隔离**，禁止在主工作区直接 `git checkout -b`：

```bash
git worktree add ../<repo>-<branch> -b <branch>
```

- 主工作区始终停留在主分支，保持干净、可随时查阅与对照。
- 分支合并后用 `git worktree remove <path>` 清理，再删除分支。

### 分层路由（agent 行为规则）

当本会话中产生以下任一类信息时，agent **主动**判断它属于哪一层，并提示用户写入对应文件——而不是顺手堆进本文件：

| 信息类型 | 目标位置 | 触发示例 |
| --- | --- | --- |
| 稳定约定（命名、目录边界、依赖方向、build/test/lint 命令、提交规范、技术栈选型） | 本文件 `AGENTS.md`（或就近子目录 `AGENTS.md`） | 「以后这个目录都按 X 命名」「依赖只能从 A → B」 |
| 任务/进度（待办、进行中、里程碑、Bug 单） | `docs/TASKS.md` | 「明天要做 X」「这个 bug 还没修」「M3 还差 Y」 |
| 决策日志 / 踩坑 / 一次性结论 | `docs/session-notes.md`（Claude Code SessionEnd hook 自动追加；其他工具下手动追写） | 「我们之所以选 X 是因为 Y」「这里有个坑：Z」 |
| 可复用流程（多步、含外部命令、含环境依赖） | `.claude/skills/<name>/SKILL.md` 或 `.cursor/rules/<name>.mdc` 等工具对应位置 | 见下「Skill / Rule 复用提示」 |

判断不清时，**问一句再写**，不要默认堆到 AGENTS.md。

### Skill / Rule 复用提示（agent 行为规则）

当你在本会话中处理以下任一类工作时，**完成后主动**提示用户把它沉淀为可复用资产：

- **重复性操作**：同一类步骤序列在本仓库出现 ≥2 次。
- **环境相关步骤**：需要特定工具链 / 凭证 / 远端机器才能跑（部署、镜像 push、CI 触发、远程数据库迁移、压测）。
- **多步复合流程**：3 步以上、含外部命令的固定 pipeline。

提示话术示例：

> 这套部署流程下次还会再用。要不要我整理成可复用资产？Claude Code 用户落到 `.claude/skills/deploy-prod/SKILL.md`，Cursor 用户落到 `.cursor/rules/deploy-prod.mdc`。下次一句话就能复用。

写入时只保留**对所有调用通用**的部分（命令、env 变量名、前置检查、失败回退），task-specific 值留作参数。

### 模块映射

本仓库为多模块结构，各模块自己的约定写在嵌套 memory 文件里（就近目录优先生效）：

| 模块 | 路径 | 子 memory 文件 |
| --- | --- | --- |
| 前端 SPA | `frontend/` | [`frontend/AGENTS.md`](./frontend/AGENTS.md) |
| REST API | `backend/` | `backend/AGENTS.md` |

在某模块子树工作时，先看该模块的 memory 文件；跨模块/全局规则才回到本根文件。

<!-- init-agents-md:end -->

<!-- BEGIN:TASK-PROTOCOL (skill-managed: init-agent-task-md v3.1.0) -->
## 任务入口协议

**用户报告的任何 bug、提出的任何需求：动代码之前，先登记任务、切对应分支。**

1. 判断 type：`bugfix`（现有行为不对）/ `feat`（新能力）/ `chore`（重构、依赖、配置、纯文档）/ `hotfix`（线上事故且等不了 dev 联调——任务描述必须写清「命中场景 → 用户影响 → 为什么等不了」，写不出就用 bugfix）。
2. 登记：`bash scripts/tasks-new.sh <type> <slug> "<一句话标题>" [priority]`，或直接按 `docs/tasks/` 现有文件的模板 Write `docs/tasks/T-<slug>.md`（文件名即 ID，无编号无锁，任何 worktree 里直接建；`T-<slug>.md` 已存在说明别人在做同一件事——先读它）。
3. 切 `<type>/<slug>` 分支，然后才开始改代码。pre-commit hook 会校验：feat/bugfix/hotfix 分支没有对应任务文件时 commit 会被拦。

**免登记白名单**（走 `chore/*` 分支或现有分支顺带，不建任务文件）：typo、纯注释/纯文档、单文件 ≤ 10 行且无行为变化。有行为变化就不是 chore 顺带——别用 chore 分支绕过校验。

**状态流转 = 直接 Edit 任务文件 frontmatter 的 `status`**（todo → doing → done → archived），改完随代码 commit，索引 `docs/TASKS.md` 由 hook 自动刷新，不用跑任何脚本：
- 开工：`status: doing` + 填 `agent` / `files`；
- merge 到 `dev` 联调通过：填 `dev_verified: <日期>`，然后 `status: done`；
- PR 合入 `main`：`status: archived`；
- 打 tag 部署 prod：`bash scripts/tasks-release.sh T-<slug>`（条目自动进 CHANGELOG 的 Unreleased 段并归档任务文件）；发版切号：`bash scripts/tasks-release.sh --cut <版本号>`。

**发版后清理（部署 prod 完成后必做）**：跑完 `tasks-release.sh`（= 该任务已上 prod）之后，**主动**检查该任务对应的 `<type>/<slug>` 本地分支与 worktree 是否还在，如果在就列出来问用户是否清理——**默认不自动删**。执行前必须先看一眼：
- 分支有未推送到 `origin` 的 commit → 先提示，别默默丢工作；
- worktree 有 uncommitted 改动 / untracked 文件（`git -C <wt> status --porcelain`）→ 先提示；
- worktree 是当前所在 worktree → 不能删自己，提示用户先切走；
- 清理动作：`git worktree remove <path>`（有变更用 `--force` 前先确认）、`git branch -d <branch>`（未合入用 `-D` 前先确认）、可选 `git push origin --delete <branch>`（远程分支要另问）。

粒度（逐个确认 / 批量确认 / dry-run 先看）由 agent 根据数量和风险自行判断，不用死板套模板。

**分支纪律**：`dev` 是 rolling 集成沙盒（可被 `reset --hard main`）；禁止 dev → main、禁止基于 dev 拉分支；每个任务从 `main` 拉分支、独立 PR 回 `main` 发版；hotfix 修完记得开 `chore/backport-hotfix-<slug>` 合回 dev。新 clone 后跑一次 `git config core.hooksPath .githooks` 启用流程 hook。
<!-- END:TASK-PROTOCOL -->

## 项目约定（手写区——skill 重跑不会碰这里）

- 技术栈：pnpm monorepo；`frontend/` React 19 + Vite，`backend/` FastAPI + PostgreSQL。
- 全仓命令：`pnpm lint && pnpm test`（提交前必须过）；后端另有 `uv run pytest backend/tests/`。
- 提交规范：Conventional Commits；分支模型「独立发版」：`dev`（rolling 集成沙盒）+ `main`（发版源），每个任务分支独立 PR 到 main 打 tag 发版。
- 依赖方向：`frontend` 只能调 `backend` 的 `/api/v1/*`，禁止直连数据库或共享代码。
