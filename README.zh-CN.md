# agent-codebase-skills

[English](./README.md) | **简体中文**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![AGENTS.md](https://img.shields.io/badge/AGENTS.md-compatible-brightgreen)](https://agents.md)
[![Claude Code](https://img.shields.io/badge/Claude_Code-skills-d97757)](https://docs.anthropic.com/en/docs/claude-code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-blue.svg)](https://github.com/Zrzzzz/agent-codebase-skills/pulls)

> Claude Code skills for using AI agents to develop and maintain **large, long-lived codebases** across many sessions.

让 agent 真正在一份代码库里**长期、可持续地**协作下去——不靠记忆奇迹，而靠把「规则 / 状态 / 流程」三类信息各归各位，每类都有 always-on 或 on-demand 的加载路径。这个仓库装三块互补的基础设施 skill。

## 一键安装

**方式一：Claude Code plugin（推荐，在任意 Claude Code 会话里执行）**：

```text
/plugin marketplace add Zrzzzz/agent-codebase-skills
/plugin install agent-codebase-skills@agent-codebase-skills
```

**方式二：安装脚本**（软链进 `~/.claude/skills/`，`git pull` 即可更新）：

```bash
curl -fsSL https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/install.sh | bash
```

两种方式**二选一**，都装会重复注册。想手动装见 [手动安装](#手动安装)。

## 收录的 skills

| Skill | 管哪一层 | 装了之后会发生什么 |
| --- | --- | --- |
| [`init-agents-md`](./init-agents-md/SKILL.md) | **稳定约定层** | 把架构 / 命名 / build-test-lint 命令 / 目录边界 / 依赖方向这些「几乎不变」的规则写进 `CLAUDE.md` 或 `AGENTS.md`（跨工具开放标准），并按 monorepo / 前后端模块拓扑生成嵌套 memory；支持 `claude` / `agents` / `both` / `migrate` 四种模式 |
| [`init-session-notes`](./init-session-notes/SKILL.md) | **会话归档层** | 装一个 SessionEnd hook：每次会话结束自动用 `claude -p` 提炼 3-8 条要点追加进 `docs/session-notes.md`；超过 45KB 自动 LLM 压缩去重 |
| [`init-agent-task-md`](./init-agent-task-md/SKILL.md) | **任务管理层**（v2 · 拆文件） | 每个任务独立成 `docs/tasks/T-XXX.md`（frontmatter + 子任务清单），多 agent 并发写入天然无冲突；`docs/TASKS.md` 由 `scripts/tasks-index.sh` 按 marker 区自动生成索引；`scripts/tasks-new.sh` 用 mkdir 锁原子分配 T-XXX 编号防撞号；`scripts/tasks-status.sh` 一步改状态 + 更新 updated + 自动刷索引；`scripts/tasks-release.sh` 上线时打印 CHANGELOG 片段并归档任务文件；生命周期与分支联动（合 develop → ✅ 已完成，合 beta → 🗄️ 历史归档，合 main → 提炼进 `CHANGELOG.md`）+ CHANGELOG 骨架；已装 init-session-notes 时可选把「自动刷索引 + 任务推进检测」挂进其 worker；老 v1 仓（monolith TASKS.md）重跑本 skill 会自动迁移 |

三个 skill **完全独立、可单装**：

- 只想要分层 memory 约定（写 AGENTS.md / CLAUDE.md）→ 装 `init-agents-md`。
- 只想要会话自动归档 → 装 `init-session-notes`。
- 只想要任务管理（拆文件任务 + TASKS.md 索引 + CHANGELOG 联动）→ 装 `init-agent-task-md`。
- 全套 → 各装一次。

> **可复用流程层**（`.claude/skills/*`）不由 skill 初始化——那是用户在跟 agent 协作过程中**临时沉淀**出来的（部署 / CI / 压测 / 远程数据库迁移这类多步外部命令流程），skill 都内置「主动提示用户把它沉淀为 skill」的行为规则，所以你只要装了它们，agent 自己会在合适的时机提醒。

## 为什么要分层

把所有项目知识塞进一份 `CLAUDE.md`（或反过来全靠 agent 记忆）有两个老问题：

1. **always-on 文件越长，每条规则的有效权重越低**——架构约定混着任务进度混着昨天的踩坑，agent 看 200 行才能定位到本次要遵的那条。
2. **生命周期混乱**——「依赖方向只能 A→B」是几年不变的；「明天要补 postgres 备份」是一周内会消失的；放一起的结果是要么频繁手改 always-on 文件、要么任务永远过期。

分层解：

```
稳定约定（年）  → CLAUDE.md / AGENTS.md      ← always-on，人手工写
易变状态（周）  → docs/session-notes.md      ← always-on（@import），hook 自动追加
                docs/TASKS.md               ← always-on（@import），随分支/部署流转
可复用流程（按需） → .claude/skills/*           ← on-demand，agent 自己决定调起
```

`init-agents-md` 把第一层装好；`init-session-notes` + `init-agent-task-md` 把第二层装好（前者管会话笔记，后者管任务视图）；第三层是 agent 在使用过程中跟用户共同长出来的。

## 装完长什么样

不用安装也能先看效果——[`examples/demo-webapp/`](./examples/demo-webapp/) 是三个 skill 在一个典型前后端 web 项目上跑完后生成文件的快照：`AGENTS.md` + 薄壳 `CLAUDE.md`、嵌套的 `frontend/AGENTS.md`、hook 自动追加的 `docs/session-notes.md`、拆文件的 `docs/tasks/` 与自动生成索引的 `docs/TASKS.md`。

## 手动安装

### 方法 A：本仓库 clone + 软链（install.sh 做的就是这个）

```bash
git clone https://github.com/Zrzzzz/agent-codebase-skills.git
cd agent-codebase-skills

mkdir -p ~/.claude/skills
ln -s "$PWD/init-agents-md"      ~/.claude/skills/init-agents-md
ln -s "$PWD/init-session-notes"  ~/.claude/skills/init-session-notes
ln -s "$PWD/init-agent-task-md"  ~/.claude/skills/init-agent-task-md
```

之后 `git pull` 就拿到最新版，无需重新装。

### 方法 B：直接复制 SKILL.md 到 `~/.claude/skills/<name>/SKILL.md`

```bash
mkdir -p ~/.claude/skills/init-agents-md ~/.claude/skills/init-session-notes ~/.claude/skills/init-agent-task-md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-agents-md/SKILL.md      -o ~/.claude/skills/init-agents-md/SKILL.md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-session-notes/SKILL.md  -o ~/.claude/skills/init-session-notes/SKILL.md
curl -L https://raw.githubusercontent.com/Zrzzzz/agent-codebase-skills/main/init-agent-task-md/SKILL.md  -o ~/.claude/skills/init-agent-task-md/SKILL.md
```

### 验证

在任意 Claude Code 会话里输入 `/`，应该能看到 `init-agents-md`、`init-session-notes`、`init-agent-task-md` 三条候选。

## 使用

进入要初始化的项目根目录，启动 Claude Code，然后：

```text
/init-agents-md       # 写 CLAUDE.md / AGENTS.md 分层约定（+ 模块嵌套 memory）
/init-session-notes   # 装 SessionEnd hook + 初始化 docs/session-notes.md
/init-agent-task-md   # 初始化 docs/tasks/ + TASKS.md 索引 + CHANGELOG.md（+ 可选会话结束自动化）
```

skill 是**幂等**的——重跑会用 sentinel 块替换已生成的部分，**不会动你手工写的内容**。可以放心在已有项目上跑、随版本升级重跑。

## 兼容性

- 必装：[Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI、`jq`、`perl`、`bash`。
- `init-agents-md` 生成的 `AGENTS.md` 是 [agents.md](https://agents.md) 开放标准，被 Codex / Cursor / Copilot / Gemini CLI / Aider / Windsurf / Zed 等 20+ 工具原生读取。
- `init-session-notes` 的 SessionEnd hook 是 Claude Code 专属机制，其他工具不会触发；`init-agent-task-md` 的任务推进自动检测挂在该 hook 的 worker 上，同样 Claude Code 专属（TASKS.md / CHANGELOG.md 本身跨工具通用）。

## 路线图

- [ ] 生成模板的英文版（memory 文件、任务文件、hook 提示词）
- [x] 打包为 Claude Code plugin，支持一条命令 `/plugin install`
- [ ] 每个 skill 的终端 GIF 演示（vhs 录制）

## 协议

[MIT](./LICENSE)
