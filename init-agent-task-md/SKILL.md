---
name: init-agent-task-md
version: 1.0.0
description: |
  为项目初始化「任务管理层」：
  1. docs/TASKS.md：T-XXX 编号任务视图，任务生命周期与分支/部署联动
     （feat/bugfix 合回 develop → ✅ 已完成；合 beta 部署 dev 服 → 🗄️ 历史归档；
     合 main 上线 prod → 提炼进 CHANGELOG.md 新版本段并从 TASKS.md 删除）。
  2. CHANGELOG.md：Keep a Changelog 骨架（不存在时创建）。
  3. 可选：若项目已装 init-session-notes 的 SessionEnd hook，把「任务推进自动检测」段
     追加到 _summarize-worker.sh 末尾（会话结束时自动标出本次完成/推进的 T-XXX）。
  本 skill 只管「任务管理」：会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)，
  CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。
  使用：/init-agent-task-md；或当用户说「给项目装任务管理」「初始化 TASKS.md」时也命中本 skill。
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# Init Agent Task MD（任务管理层初始化）

为项目装一套**与 Git 分支/部署联动**的任务管理：`docs/TASKS.md` 用 `T-序号` 登记任务，条目随代码流转——合回 `develop` 进「✅ 已完成」，合 `beta` 部署 dev 服进「🗄️ 历史归档」，合 `main` 上线 prod 提炼进 `CHANGELOG.md`。多 agent 并行时靠 `@agent-id` 认领 + 影响文件通配避免抢任务。

> ⚠️ 该 skill 只管任务管理层。会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)；CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。三者**完全独立**，可单装；想要全套就各跑一次。

---

## Step 0：探测项目状态

```bash
git rev-parse --git-dir 2>/dev/null >/dev/null && echo "git=yes" || echo "git=no"
git branch -a 2>/dev/null | grep -E 'develop|beta|main|master' | head -10
TASKS_FILE=""
for f in "docs/TASKS.md" "TASKS.md" "TODO.md" "docs/TODO.md"; do
  [ -f "$f" ] && TASKS_FILE="$f" && break
done
[ -n "$TASKS_FILE" ] && echo "tasks=$TASKS_FILE" || echo "tasks=none"
[ -f CHANGELOG.md ] && echo "changelog=exists" || echo "changelog=new"
[ -f .claude/hooks/_summarize-worker.sh ] && echo "worker=exists" || echo "worker=none"
[ -f .claude/hooks/_summarize-worker.sh ] && grep -q '任务文档检查' .claude/hooks/_summarize-worker.sh && echo "taskcheck=installed" || echo "taskcheck=absent"
```

- **已有任务文档时不覆盖**：展示其现有结构，用 `AskUserQuestion` 询问「保持不动 / 帮我迁移到本模板（人工确认每一段去向）」；默认不动。
- **分支模型确认**：模板假定 `develop`（日常开发）→ `beta`（dev 服发布）→ `main`（prod 发布）三段。若探测到的分支不符（如只有 `main`、或用 `dev`/`staging`），用 `AskUserQuestion` 让用户确认各阶段对应的分支名，写模板时替换。分支只有一段的项目可把生命周期简化为「已完成 → CHANGELOG」两跳，删掉「历史归档」段。

---

## Step 1：写入 docs/TASKS.md

仅在无任务文档（或用户选择迁移）时写入。`<项目名>` / 分支名按 Step 0 结果替换，`updated:` 用当天日期：

```markdown
---
project: <项目名>
updated: <YYYY-MM-DD>
---

# 进度 · <项目名>

> **更新协议**
> - 任务用 `T-序号` 编号，子任务是它的勾选清单——勾到哪就是进展到哪。
> - 开始任务 → 移入「🔨 进行中」，并在任务后标 `@agent-id` 认领（多 agent 时避免抢同一个）。
> - **任务生命周期（与分支/部署联动）**：
>   1. feat/bugfix 合回 `develop` → 条目移到「✅ 已完成」并标日期；
>   2. 合 `beta` 部署 dev 服 → 把「✅ 已完成」中随本次发版的条目移到「🗄️ 历史归档」并标部署日期；
>   3. 合 `main` 上线 prod → 把「🗄️ 历史归档」中随本次上线的条目提炼成 Keep a Changelog 条目写入 `CHANGELOG.md` 新版本段，然后从本文件删除。
> - 踩坑 / 定下的决策记到底部「🧭 约束与决策」「⚠️ 踩坑与教训」。
> - 挑任务时优先选影响文件不重叠的，减少并行冲突。更新顶部 `updated:`。
> - **新增 feat/bugfix 前必须在此登记**：`feat/<slug>` → `T-XXX`（feat 类），`bugfix/<slug>` → `T-XXX`（fix 类），把子任务列全再动手。

## 🔨 进行中

_（暂无。开分支前先在这里登记 T-XXX + 子任务清单，再动手。）_

## 📋 待办（优先级从上到下）

_（按需登记。示例：`- [ ] **T-001** · <一句话讲清做什么> · 影响文件: <路径通配>`）_

## ✅ 已完成（develop 已合入，待发 dev 服）

_（feat/bugfix 合回 `develop` 后移到这里，标日期与执行者。）_

## 🗄️ 历史归档（已部署 dev 服，待上线 prod）

_（合 `beta` 部署 dev 服后移到这里并标部署日期；合 `main` 上线 prod 后提炼进 `CHANGELOG.md` 新版本段，并从本文件删除。）_

---

## 🧭 约束与决策（只增不删）

_（格式：`- **D-N** (YYYY-MM-DD)：<决策> — 原因：<...>`）_

## ⚠️ 踩坑与教训

_（写这里的都是「已经付出过代价的教训」，不写空口猜想。格式：`<坑> → 根因：<...> → 结论：<...>`）_
```

---

## Step 2：写入 CHANGELOG.md（不存在时）

```markdown
# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

条目来源：合 `main` 上线 prod 时，由 [`docs/TASKS.md`](docs/TASKS.md)「🗄️ 历史归档」中随本次上线的任务提炼而来（流程见 TASKS.md 更新协议）。

## [Unreleased]
```

已存在 CHANGELOG.md 时不动内容，只建议用户在文件头补一行「条目来源」说明。

---

## Step 3：把生命周期约定挂进 CLAUDE.md（可选）

若项目有 `CLAUDE.md`，用 `AskUserQuestion` 询问是否补充发布规范联动（用户已有 Git 规范段就**插进对应条目**，没有就加一小节）。要点三条：

- 开 `feat/**` / `bugfix/**` 前必须在 `docs/TASKS.md` 登记 T-XXX（子任务清单 + `@agent-id` 认领 + 影响文件通配）；合回 `develop` 后移「✅ 已完成」。
- 合 `beta` 部署 dev 服成功后，把「✅ 已完成」中随本次发版的条目移到「🗄️ 历史归档」并标部署日期。
- 合 `main` 上线 prod 后，把「🗄️ 历史归档」中随本次上线的条目提炼成 `CHANGELOG.md` 新版本段（Keep a Changelog 格式），并从 TASKS.md 删除。

同时建议把 `@docs/TASKS.md` 加进 CLAUDE.md 的 import 列表（若采用了 import 约定），让每次会话自动加载任务视图。

---

## Step 4：追加任务推进自动检测（可选，需已装 init-session-notes）

仅当 Step 0 探测 `worker=exists` 且 `taskcheck=absent` 时，用 `AskUserQuestion` 询问是否安装。确认后把以下内容**原样追加**到 `.claude/hooks/_summarize-worker.sh` 末尾（该 worker 由 `init-session-notes` 安装，会话结束时在追加 session 提炼之后跑到这里）：

```bash

# ── 任务文档检查（Task Doc Auto-Check，由 init-agent-task-md 安装）──
tasks_file=""
for candidate in "$cwd/docs/TASKS.md" "$cwd/TASKS.md" "$cwd/TODO.md" "$cwd/docs/TODO.md"; do
  [ -f "$candidate" ] && tasks_file="$candidate" && break
done

if [ -n "$tasks_file" ]; then
  tasks_pending="$(awk '
    /^## .*(进行中|待办|In Progress|Todo|TODO|Pending)/ { in_section=1; next }
    /^## / { in_section=0 }
    in_section { print }
  ' "$tasks_file" | head -c 8000)"

  if [ -n "$tasks_pending" ]; then
    task_prompt="下面是一次 Claude Code 开发会话记录，以及项目当前的未完成任务列表。

请分析本次会话，判断哪些任务被完成或有明显推进。仅报告有实质证据（代码已提交/功能已验证/问题已解决）的任务。

输出格式（严格按此）：
- 如有完成的任务：输出 markdown 无序列表，每条格式为「✅ [任务简称]：一句话说明完成了什么」
- 如有推进但未完成的任务：输出「🔄 [任务简称]：一句话说明推进了什么」
- 如无实质推进：只输出一行 NONE

未完成任务列表：
$tasks_pending

会话记录（节选）：
$(printf '%s' "$convo" | tail -c 20000)"

    task_check="$(CLAUDE_SESSION_SUMMARY_RUNNING=1 claude -p "$task_prompt" --settings '{"disableAllHooks":true}' 2>>"$log")"

    if [ -n "$task_check" ] && [ "$(printf '%s' "$task_check" | tr -d '[:space:]')" != "NONE" ]; then
      {
        printf '\n**任务进度（自动检测）：**\n\n'
        printf '%s\n' "$task_check"
      } >> "$notes"
    fi
  fi
fi
```

`worker=none`（未装 init-session-notes）时跳过本步，并在报告里提示：想要自动检测先跑 `/init-session-notes`，再回来重跑本 skill。

---

## Step 5：输出初始化报告

```
✅ 任务管理层已初始化：

  • docs/TASKS.md          （[新建/已存在保留/已迁移]）
  • CHANGELOG.md           （[新建/已存在保留]）
  • CLAUDE.md 发布联动约定  （[已补充/用户跳过/无 CLAUDE.md]）
  • 任务推进自动检测        （[已追加到 _summarize-worker.sh/未装 init-session-notes 跳过/用户跳过/已存在]）

任务生命周期：
  feat/bugfix 合回 develop → ✅ 已完成
  合 beta 部署 dev 服      → 🗄️ 历史归档
  合 main 上线 prod        → 提炼进 CHANGELOG.md 并从 TASKS.md 删除

下一步建议：
  1. 在 docs/TASKS.md「📋 待办」写下当前 1–3 个任务（T-001 起编号）
  2. TASKS.md 变大后，把陈旧内容拆到 docs/TASKS-archive.md 只留指针（避免撑大每次会话的上下文）
```

---

## 注意事项

- **已有任务文档时默认不动**：用户的历史任务记录珍贵；迁移必须逐段确认去向（进行中/待办/已完成/归档），不许静默重写。
- **归档纪律**：TASKS.md 若被 CLAUDE.md `@` import，每次会话都整文件进上下文——历史条目一多就该拆 `docs/TASKS-archive.md`（只读存档 + 正文留指针），别让进度文件变成流水账。
- **awk 探测的章节名**：检测段匹配 `## ` 开头且含「进行中/待办/In Progress/Todo/TODO/Pending」的标题（兼容 `## 🔨 进行中` 这类带 emoji 前缀的写法）；改了章节命名就要同步改 worker 正则。
- **检测段依赖 worker 的变量**：追加的代码用到 `$cwd` / `$convo` / `$log` / `$notes`，只能追加在 `_summarize-worker.sh` 末尾，不能独立成脚本；`init-session-notes` 重装覆盖 worker 后需重跑本 skill 补回（探测 `taskcheck=absent` 即可发现）。
- **分支名是参数不是常量**：模板里的 `develop` / `beta` / `main` 按项目实际分支替换；没有多级发布的项目直接砍掉「历史归档」段，两跳即可。
- **绝对禁止 `rm`**：删除任何文件时用 `trash`（用户级全局约定）。
