---
name: init-agents-md
version: 1.0.0
description: |
  为项目初始化「分层 memory 约定」——把跨工具通用规则写到 CLAUDE.md / AGENTS.md，
  支持模块嵌套 memory（前后端拆分 / monorepo 的 apps、packages、services），
  并支持在 CLAUDE.md ↔ AGENTS.md 之间迁移内容。
  支持四种模式：
    - claude：只写 CLAUDE.md（Claude Code 专属）
    - agents：只写 AGENTS.md（跨工具开放标准）
    - both：AGENTS.md 放跨工具通用 + CLAUDE.md 做薄壳引用
    - migrate：把现有 CLAUDE.md 内容拆/转到 AGENTS.md（或反向）
  本 skill 只管「约定层」：不装 SessionEnd hook——那归
  [`init-session-notes`](../init-session-notes/SKILL.md)；不初始化 TASKS.md 任务管理——
  那归 [`init-agent-task-md`](../init-agent-task-md/SKILL.md)。
  使用：/init-agents-md；或当用户说「为这个项目加上分层约定」「把 CLAUDE.md 迁移到 AGENTS.md」时也命中本 skill。
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# Init AGENTS.md / CLAUDE.md（约定层初始化）

为项目初始化**稳定约定层**——把架构、命名、build/test 命令、目录边界、依赖方向这类几乎不变的全局规则写到 always-on memory 文件（CLAUDE.md 或 AGENTS.md），并按模块拓扑写嵌套 memory。

> ⚠️ 该 skill 只写 memory 文件。会话归档（SessionEnd hook + `docs/session-notes.md`）归 [`init-session-notes`](../init-session-notes/SKILL.md)；任务管理（`docs/TASKS.md` + CHANGELOG 联动）归 [`init-agent-task-md`](../init-agent-task-md/SKILL.md)。三者**完全独立**，可单装；想要全套就各跑一次。

---

## Step 0：询问 memory 模式

用 `AskUserQuestion` 问：

**用哪个 memory 文件做稳定约定层？**

- `CLAUDE.md`（Claude Code 专属）：只在 Claude Code 工作，可用 `@path` 直接 import session-notes/TASKS，加载粒度最细。
- `AGENTS.md`（跨工具开放标准，推荐多工具用户）：被 Codex / Cursor / Copilot / Gemini CLI / Aider / Windsurf / Zed 等 20+ 工具原生读取，已被 6 万多个仓库采用。
- `两者都要`：AGENTS.md 放跨工具通用规则；CLAUDE.md 做薄壳，仅包含 Claude 专属配置（`@imports` / permissions / MCP server）并指向 AGENTS.md。
- `迁移模式`：把现有 CLAUDE.md 内容拆/转到 AGENTS.md（或反向）。→ 跳到 [Migration 流程](#migration-流程)。

把答案记为 `$MEMORY_MODE`（claude / agents / both / migrate）。

---

## Step 1：探测项目状态

用 Bash 一次性探测：

```bash
git rev-parse --git-dir 2>/dev/null >/dev/null && echo "git=yes" || echo "git=no"
[ -f CLAUDE.md ] && echo "claude_md=exists" || echo "claude_md=new"
[ -f AGENTS.md ] && echo "agents_md=exists" || echo "agents_md=new"
[ -d .claude/skills ] && echo "skills_dir=exists" || echo "skills_dir=new"

# 探测仓库模块拓扑（monorepo / 前后端拆分 / 微服务）
echo "── modules ──"
for d in frontend backend web server api client admin mobile worker scheduler; do
  [ -d "$d" ] && echo "module=$d"
done
[ -d apps ]      && ls -1 apps      2>/dev/null | head -20 | sed 's/^/module=apps\//'
[ -d packages ]  && ls -1 packages  2>/dev/null | head -20 | sed 's/^/module=packages\//'
[ -d services ]  && ls -1 services  2>/dev/null | head -20 | sed 's/^/module=services\//'
[ -f pnpm-workspace.yaml ] || [ -f lerna.json ] || [ -f turbo.json ] || [ -f nx.json ] && echo "monorepo=js"
[ -f go.work ]   && echo "monorepo=go"
[ -f Cargo.toml ] && grep -q '^\[workspace\]' Cargo.toml 2>/dev/null && echo "monorepo=rust"
[ -f pyproject.toml ] && grep -q 'tool.uv.workspace\|tool.poetry.workspaces' pyproject.toml 2>/dev/null && echo "monorepo=py"
```

对已存在的 memory 文件：用**幂等块替换**（见 Step 2），不询问；保留用户在 sentinel 块**外**写的任何内容。

把 `module=` 行收集成 `$MODULES` 列表，后续 [Step 3](#step-3写入嵌套-memory-文件功能模块分层) 用。

---

## Step 2：写入根 memory 文件

根据 `$MEMORY_MODE` 决定写入哪个文件：

| MEMORY_MODE | 写入 |
| --- | --- |
| `claude` | `CLAUDE.md`（用模板 A） |
| `agents` | `AGENTS.md`（用模板 B） |
| `both` | `AGENTS.md`（模板 B）+ `CLAUDE.md`（薄壳模板 C，引用 AGENTS.md） |
| `migrate` | 见 [Migration 流程](#migration-流程) |

### 幂等写入规则

每个目标文件用 sentinel 包裹整块内容，让重复执行 skill 时**只替换块内、不动用户其他内容**：

```markdown
<!-- init-agents-md:begin v1 -->
（此处为 skill 维护的分层声明块）
<!-- init-agents-md:end -->
```

写入算法：
1. 文件不存在：Write 整文件（含 sentinel 块）。
2. 文件存在且含 `<!-- init-agents-md:begin` ：用 Edit 把两个 sentinel 之间的整段替换为新块。
3. 文件存在但无 sentinel：用 Edit 在文件末尾追加（前面留一空行），不动既有内容。

> 兼容性：若文件里仍有旧版 `<!-- init-progress-manager:begin v2 -->` sentinel（来自已废弃的 init-progress-manager skill），同样视作本 skill 的块，整段替换为 `init-agents-md:begin v1`。

### 模板 A：`CLAUDE.md`（claude 模式）

```markdown
<!-- init-agents-md:begin v1 -->
## 协作约定（由 init-agents-md 维护）

本项目采用「**约定 / 状态 / 流程**」三层分层，避免把不同生命周期的信息混在同一份 always-on 文件里：

| 层 | 文件 | 由谁维护 |
| --- | --- | --- |
| 稳定约定 | 本文件 `CLAUDE.md` | 人手工编辑（架构、命名、build/test 命令、目录边界、依赖方向） |
| 易变状态 | `docs/session-notes.md` `docs/TASKS.md` | SessionEnd hook 自动追加 + 人工裁剪（需另跑 `/init-session-notes` 安装） |
| 可复用流程 | `.claude/skills/*` | 重复/环境相关流程沉淀成 skill，按需调起 |

会话上下文加载（由 Claude Code 自动 import；若文件不存在，删掉对应行）：

@docs/session-notes.md
@docs/TASKS.md

### 写本文件的纪律
- 只放**几乎不变**的全局规则；任务进度、决策日志、踩坑记录不要写在这里，让它们留在 session-notes / TASKS。
- 控制长度。always-on 文件越长越杂，单条规则的有效权重越低。

### 分支纪律（agent 行为规则）

开新分支**必须用 `git worktree` 隔离**，禁止在主工作区直接 `git checkout -b`：

```bash
git worktree add ../<repo>-<branch> -b <branch>
```

- 主工作区始终停留在主分支，保持干净、可随时查阅与对照。
- 分支合并后用 `git worktree remove <path>` 清理，再删除分支。

### 分层路由（agent 行为规则）

当本会话中产生以下任一类信息时，你（Claude）**主动**判断它属于哪一层，并提示用户写入对应文件——而不是顺手堆进本文件：

| 信息类型 | 目标位置 | 触发示例 |
| --- | --- | --- |
| 稳定约定（命名、目录边界、依赖方向、build/test/lint 命令、提交规范、技术栈选型） | 本文件 `CLAUDE.md` | 「以后这个目录都按 X 命名」「依赖只能从 A → B」 |
| 任务/进度（待办、进行中、里程碑、Bug 单） | `docs/TASKS.md` | 「明天要做 X」「这个 bug 还没修」「M3 还差 Y」 |
| 决策日志 / 踩坑 / 一次性结论 | `docs/session-notes.md`（SessionEnd hook 自动追加，无需手动） | 「我们之所以选 X 是因为 Y」「这里有个坑：Z」 |
| 可复用流程（多步、含外部命令、含环境依赖） | `.claude/skills/<name>/SKILL.md` | 见下「Skill 复用提示」 |

判断不清时，**问一句再写**，不要默认堆到 CLAUDE.md。

### Skill 复用提示（agent 行为规则）

当你（Claude）在本会话中处理以下任一类工作时，**完成后主动**提示用户把它沉淀为 skill：

- **重复性操作**：同一类步骤序列在本仓库出现 ≥2 次（如多次手动复现某个本地起服 + 验证流程）。
- **环境相关步骤**：需要特定工具链 / 凭证 / 远端机器才能跑（部署、镜像 push、CI 触发、远程数据库迁移、压测、生产数据导出）。
- **多步复合流程**：3 步以上、含外部命令的固定 pipeline（如 `build → smoke test → deploy → 通知`）。

提示话术示例：

> 这套部署流程下次还会再用。要不要我把它整理成 `.claude/skills/deploy-prod/SKILL.md`，下次直接 `/deploy-prod` 就能复用？
> 我会把确定性的命令、必需的 env vars、前置检查、失败回退步骤都写进去，user-specific 的值留作参数。

用户确认后，按 [Anthropic Skills 规范](https://github.com/anthropics/skills) 在 `.claude/skills/<kebab-name>/SKILL.md` 写入 YAML frontmatter（`name` / `description` / `allowed-tools`）+ 步骤化指令；只写**对所有调用通用**的部分，task-specific 值留作参数。

<!-- init-agents-md:end -->
```

### 模板 B：`AGENTS.md`（agents / both 模式）

```markdown
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

<!-- init-agents-md:end -->
```

### 模板 C：`CLAUDE.md` 薄壳（both 模式下）

```markdown
<!-- init-agents-md:begin v1 -->
## Claude Code 专属配置

本仓库的跨工具通用约定写在 [AGENTS.md](./AGENTS.md)，请先读那一份。本文件只放 Claude Code 专属的内容。

### 会话上下文 import（Claude Code 特性；若文件不存在，删掉对应行）

@AGENTS.md
@docs/session-notes.md
@docs/TASKS.md

### Skill 复用提示

参见 AGENTS.md 中「Skill / Rule 复用提示」一节，本文件不重复。Claude Code 用户调起方式为 `/<skill-name>`。

<!-- init-agents-md:end -->
```

---

## Step 3：写入嵌套 memory 文件（功能模块分层）

仓库内常见模块拓扑（前后端拆分、monorepo 的 `apps/*` / `packages/*` / `services/*`、独立 worker 等）应当在**模块根目录**各自放一份 memory 文件——AGENTS.md / CLAUDE.md 都支持「就近目录优先」加载，agent 在该子树工作时自动加载这一份，不必把模块特异的规则塞进根文件污染全局 context。

### 触发条件
Step 1 探测到 `$MODULES` 非空，或用户在 Step 0 后明确说仓库是 monorepo / 前后端分离。

### 执行流程

1. **展示拓扑**：把探测到的模块列出来给用户看，例如：
   ```
   检测到以下模块：
     • frontend/       （疑似前端：含 package.json + src/）
     • backend/        （疑似后端：含 pyproject.toml + src/）
     • apps/admin-web  （来自 pnpm-workspace）
     • services/worker （含 Dockerfile）
   ```

2. **用 `AskUserQuestion` 多选**：「为哪些模块写嵌套 memory 文件？」选项包括：
   - 每个检测到的模块（multiSelect）
   - 「全部」/「先不写,以后手动加」

3. **每个选中的模块**写入 `<module>/CLAUDE.md` 或 `<module>/AGENTS.md`（跟根 memory 文件同种格式，由 `$MEMORY_MODE` 决定），用同样的 sentinel 块。**内容比根文件短得多**——只放该模块特有的 delta。

4. **回填根文件**：在根 memory 文件的 sentinel 块里加一个「模块映射表」段落，列出已生成的嵌套文件位置,让 agent 在根目录工作时也知道下钻方向。

### 嵌套模板（适用 CLAUDE.md / AGENTS.md，两种语法一致）

```markdown
<!-- init-agents-md:begin v1 nested -->
## <模块名> 模块约定（由 init-agents-md 维护）

> 本文件是仓库根 [`AGENTS.md`](../AGENTS.md) 的子目录延伸——根约定全部继承，本文件只写本模块特有的 delta。

### 范围
本目录及其子目录的代码归本文件管。跨模块的规则（命名、提交、CI、依赖方向）不要写在这里，那些归根 memory 文件。

### 模块特征（按需填写，删掉不适用的）
- **职责**：（一句话说明本模块在仓库里负责什么——前端 SPA / REST API / 异步 worker / 共享库 …）
- **技术栈**：（语言 + 框架 + 关键依赖，仅本模块特有部分）
- **启动 / 构建 / 测试命令**：
  ```bash
  # 本模块的 build / dev / test，例如：
  # pnpm --filter <pkg> dev
  # uv run pytest tests/
  ```
- **目录边界**：本模块允许依赖哪些其他模块？被哪些模块依赖？（防止依赖方向反向）
- **本模块特有约定**：（API 路由前缀、组件命名、消息格式、数据库 schema 归属、不要碰的文件 …）

### 分层路由（本模块内）
- 本模块特有约定 → 本文件
- 仓库级通用约定 → 根 memory 文件
- 任务/进度 → 仓库根 `docs/TASKS.md`（用 `[<模块名>]` 前缀区分）
- 决策/踩坑 → 仓库根 `docs/session-notes.md`（hook 自动追加，无需手动）
- 本模块特有的可复用流程（如「本模块部署」「本模块种子数据重置」）→ `.claude/skills/<module>-<action>/`

<!-- init-agents-md:end -->
```

### 根 memory 文件回填段（追加到根 sentinel 块内）

```markdown
### 模块映射

本仓库为多模块结构，各模块自己的约定写在嵌套 memory 文件里（就近目录优先生效）：

| 模块 | 路径 | 子 memory 文件 |
| --- | --- | --- |
| <模块 1> | `<path>/` | [`<path>/AGENTS.md`](./<path>/AGENTS.md) |
| <模块 2> | `<path>/` | [`<path>/AGENTS.md`](./<path>/AGENTS.md) |

在某模块子树工作时，先看该模块的 memory 文件；跨模块/全局规则才回到本根文件。
```

### 写本模块文件的纪律
- **短**。嵌套文件只放模块 delta，根文件已说过的不重复。一旦嵌套文件 > 100 行,先想想是不是有内容该提到根文件、或者该拆 skill。
- **不重复路由表**。根文件已有「分层路由」总表，嵌套文件里只在「分层路由（本模块内）」标注本模块特殊点（比如 TASKS 用前缀区分）。
- **不写跨模块规则**。比如「提交信息用 Conventional Commits」是仓库级的，不要在 `frontend/AGENTS.md` 里重复一遍。

---

## Migration 流程（`$MEMORY_MODE == migrate`）

用 `AskUserQuestion` 问迁移方向：

- `CLAUDE.md → AGENTS.md`：仓库希望开始用跨工具开放标准。
- `AGENTS.md → CLAUDE.md`：仓库决定专注 Claude Code（很少用，但支持）。
- `CLAUDE.md → AGENTS.md + 保留薄壳 CLAUDE.md`（推荐）：相当于切到 `both` 模式。

执行步骤：

1. **Read 源文件全文**。
2. **拆分内容**。用 `claude -p`（在 skill 内可直接调起 LLM 推理）让 LLM 按以下规则把源文件分两类：
   - **跨工具通用**（命名规范、build/test/lint 命令、目录边界、依赖方向、架构约定、Conventional Commits 之类的规则、CHANGELOG 规则、提示词设计原则等通用工程纪律）→ 写入**目标文件**。
   - **工具专属**（`@imports`、Claude Code permissions、MCP server 配置、`/<skill>` 调起方式、settings.local.json 引用、Cursor 的 `.mdc` glob 等）→ 留在**源文件**或新薄壳。
3. **Diff 展示**给用户两个文件的最终内容（包括 sentinel 块），明确「这部分搬去 AGENTS.md，这部分留在 CLAUDE.md」。
4. **用户批准后**用 Edit/Write 写入两份文件：
   - 目标文件用 Step 2 的 sentinel 块包裹通用部分。
   - 源文件保留工具专属内容 + 在顶部加一条指针：`> 跨工具通用约定已迁移到 [AGENTS.md](./AGENTS.md)，先读那一份。`
5. **不要**删除源文件（用户可能仍需 Claude 专属配置），除非用户明确确认「源文件没有任何独有内容」。

---

## Step 4：输出初始化报告

向用户输出：

```
✅ 约定层已初始化（模式：<MEMORY_MODE>）：

  根 memory：
    • <CLAUDE.md 或 AGENTS.md>（[新建/已更新块/已追加块]）
  嵌套（按模块）：
    • <frontend>/AGENTS.md   [新建/跳过]
    • <backend>/AGENTS.md    [新建/跳过]
    （未检测到模块拓扑或用户选择不写时，本节省略）

下一步建议：
  1. 打开 <memory 文件> 检查 sentinel 块，补充本项目特有的 build/test/lint 命令与目录边界
  2. 若需要会话自动归档 + 任务推进检测，运行 `/init-session-notes` 装 SessionEnd hook
  3. 接下来对话中遇到部署/CI/压测等环境相关流程，我会主动提示把它沉淀为 skill
```

---

## 注意事项

- **不动 hook、不写 TASKS.md**：本 skill 只管 memory 文件。会话归档与任务文档归 [`init-session-notes`](../init-session-notes/SKILL.md) skill。
- **memory 文件保持精简**：sentinel 块约 60–80 行已是上限；项目特有的 build/test 命令、目录约定由用户在块外手工写。always-on 文件越长，单条规则的有效权重越低。
- **嵌套 memory 文件只放 delta**：模块级 `frontend/AGENTS.md` 等不重复根文件已说过的规则；agent 在子树工作时**两份都加载**（根 + 最近目录），重复内容会双倍占 context 而毫无收益。
- **重复执行安全**：所有 memory 文件改动用 sentinel 幂等块替换，不会破坏用户自己写的内容。
- **兼容旧 sentinel**：旧版 `<!-- init-progress-manager:begin v2 -->` 块同样视作本 skill 维护范围，整段替换为 `init-agents-md:begin v1`。
- **绝对禁止 `rm`**：删除任何文件时用 `trash`（用户级全局约定）；本 skill 本身不删文件，迁移流程也只增量改写，不会触发删除。
