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

## 项目约定（手写区——skill 重跑不会碰这里）

- 技术栈：pnpm monorepo；`frontend/` React 19 + Vite，`backend/` FastAPI + PostgreSQL。
- 全仓命令：`pnpm lint && pnpm test`（提交前必须过）；后端另有 `uv run pytest backend/tests/`。
- 提交规范：Conventional Commits；分支模型 `develop` → `beta` → `main`。
- 依赖方向：`frontend` 只能调 `backend` 的 `/api/v1/*`，禁止直连数据库或共享代码。
