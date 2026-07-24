---
name: init-agent-task-md
version: 3.1.0
description: |
  为项目初始化「任务管理层」v3——协调靠结构消除、纪律靠 hook 兜底、脚本只留便利：
  1. docs/tasks/T-<slug>.md：每个任务一份独立文件，**文件名即 ID**——无编号、
     无锁、无主树限制，任何 agent 在任何 worktree 里直接建文件直接 commit。
  2. docs/TASKS.md：marker 区索引视图，由 git hook（pre-commit / post-merge）
     自动重生成——没人需要「记得跑脚本」；marker 之外（更新协议 / 约束与决策 /
     踩坑与教训）由人手写，脚本不动。
  3. .githooks/pre-commit：流程纪律兜底——feat/bugfix/hotfix 分支必须有对应
     任务文件才能 commit；禁止直接 commit 到 main；docs/tasks 变更自动刷索引。
  4. .githooks/post-merge：主 checkout pull/merge 后自动刷索引。
  5. CLAUDE.md / AGENTS.md「任务入口协议」（必装 marker 块）：用户报 bug /
     提需求 → 先登记任务 + 切分支，再动代码；免登记白名单写死。
  6. scripts/tasks-new.sh（模板便利，无锁）、scripts/tasks-index.sh（hook 调用）、
     scripts/tasks-release.sh（条目直接写进 CHANGELOG 的 Unreleased 段 +
     --cut 切版本）。v2 的 tasks-status.sh 已删——status 流转就是一行
     frontmatter Edit，updated 字段已砍（由 git log 派生）。
  7. CHANGELOG.md：Keep a Changelog 骨架（不存在时创建）。
  8. 可选：把「自动跑索引 + 任务推进检测」追加进 init-session-notes 的
     _summarize-worker.sh，作为会话结束兜底。

  幂等升级：重跑 skill 按 scripts/tasks-index.sh 里的 skill-managed 版本号
  分流——v1（monolith TASKS.md）与 v2.x（顺序编号 + 四脚本）都走迁移到 v3；
  已是 v3.x 只覆盖脚本与 hook 文件。

  本 skill 只管「任务管理」：会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)，
  CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。
  使用：/init-agent-task-md；或当用户说「给项目装任务管理」「初始化 TASKS.md」
  「让 agent 先开任务再改代码」时也命中本 skill。
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# Init Agent Task MD v3（任务管理层 · 无编号 + hook 自动化）

v3 的三条设计原则（对应 v2 暴露的三个痛点）：

1. **协调靠结构消除**：v2 的 T-XXX 顺序编号需要全局协调（mkdir 锁、必须回主树跑、`mv` 进 worktree），v3 改为**文件名即 ID**——`docs/tasks/T-<slug>.md`。slug 本来就要起（分支名要用），两个 agent 起了同一个 slug 说明在做同一件事，这是要暴露的语义冲突而不是要靠锁避开的编号冲突。锁、主树限制、mv 编排全部消失。
2. **纪律靠 hook 兜底**：索引刷新和流程校验挂 git hook（`.githooks/pre-commit` + `post-merge`），不再依赖"agent 记得跑脚本"。feat/bugfix/hotfix 分支没登记任务 → commit 被拦；直接 commit main → 被拦；docs/tasks 变更 → 索引自动重生成并带进本次 commit。
3. **脚本只留便利**：`updated` 字段砍掉（由 `git log` 派生），status 流转退化为**一行 frontmatter Edit**，v2 的 `tasks-status.sh` 随之删除。agent 的日常动作只剩三个：**建文件、改 frontmatter、commit**。

生命周期（默认「独立发版」模型）：`status: doing` 开工 → 分支 merge 到 `dev` 联调（填 `dev_verified`）→ 联调通过 `status: done` → PR 合入 `main` → `status: archived` → 打 tag 部署 prod → `tasks-release.sh` 把条目写进 CHANGELOG 并归档任务文件。**dev 是 rolling 集成沙盒**（可被 `reset --hard main`，不流回 main），每个任务在 main 上独立打 tag 发版。**hotfix 跳 dev**：从 main 切 `hotfix/<slug>` → 修 → PR 回 main → tag，事后 backport 回 dev。

> ⚠️ 该 skill 只管任务管理层。会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)；CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。三者**完全独立**，可单装。

---

## Step 0：探测项目状态 + 已装版本

```bash
CURRENT_VERSION="3.1.0"

git rev-parse --git-dir 2>/dev/null >/dev/null && echo "git=yes" || echo "git=no"
git branch -a 2>/dev/null | grep -E 'develop|dev|beta|main|master' | head -10

# 任务文档 & 目录
[ -d docs/tasks ] && echo "tasks_dir=exists" || echo "tasks_dir=none"
TASKS_FILE=""
for f in "docs/TASKS.md" "TASKS.md" "TODO.md" "docs/TODO.md"; do
  [ -f "$f" ] && TASKS_FILE="$f" && break
done
[ -n "$TASKS_FILE" ] && echo "tasks_file=$TASKS_FILE" || echo "tasks_file=none"

# 索引脚本 + 版本号
INSTALLED_VERSION=""
if [ -f scripts/tasks-index.sh ]; then
  INSTALLED_VERSION="$(grep -oE 'skill-managed: init-agent-task-md v[0-9]+\.[0-9]+\.[0-9]+' scripts/tasks-index.sh | head -1 | awk -F'v' '{print $NF}')"
fi
echo "installed_version=${INSTALLED_VERSION:-none}"
echo "current_version=$CURRENT_VERSION"

# TASKS.md 中是否已有 marker
if [ -n "$TASKS_FILE" ] && grep -qF 'BEGIN:TASKS-INDEX' "$TASKS_FILE" 2>/dev/null; then
  echo "marker=present"
else
  echo "marker=absent"
fi

# git hooks 环境（v3 要装 .githooks）
HOOKS_PATH="$(git config --get core.hooksPath 2>/dev/null || true)"
echo "hooks_path=${HOOKS_PATH:-unset}"
[ -d .husky ] && echo "husky=yes" || echo "husky=no"
[ -f .githooks/pre-commit ] && grep -q 'init-agent-task-md' .githooks/pre-commit && echo "taskhook=installed" || echo "taskhook=absent"

# CLAUDE.md / AGENTS.md 入口协议
PROTO_FILE=""
for f in "CLAUDE.md" "AGENTS.md"; do
  [ -f "$f" ] && grep -qF 'BEGIN:TASK-PROTOCOL' "$f" && PROTO_FILE="$f" && break
done
echo "protocol=${PROTO_FILE:-absent}"

# CHANGELOG 与 session-notes worker
[ -f CHANGELOG.md ] && echo "changelog=exists" || echo "changelog=new"
[ -f .claude/hooks/_summarize-worker.sh ] && echo "worker=exists" || echo "worker=none"
[ -f .claude/hooks/_summarize-worker.sh ] && grep -q '任务文档检查' .claude/hooks/_summarize-worker.sh && echo "taskcheck=installed" || echo "taskcheck=absent"
[ -f .claude/hooks/_summarize-worker.sh ] && grep -q 'tasks-index.sh' .claude/hooks/_summarize-worker.sh && echo "autoindex=installed" || echo "autoindex=absent"
```

**根据探测结果分流**：

| 状态 | 分类 | 该走哪条路径 |
| --- | --- | --- |
| `tasks_dir=none` 且 `tasks_file=none` | 全新装 | **Path A**：从零建 |
| `tasks_file` 有内容且 `marker=absent` 且 `tasks_dir=none` | v1 老版仓 | **Path B**：迁移到 v3（先按 v1→v2 的拆文件逻辑拆，再套 v3 命名） |
| `tasks_dir=exists` 且 `installed_version` 是 2.x | v2 仓 | **Path B**：迁移到 v3（改名 + 删字段 + 换脚本 + 装 hook）|
| `tasks_dir=exists` 且 `installed_version` 是 3.x | 已是 v3 | **Path C**：重装/升级（只覆盖脚本与 hook，正文不动） |

**分支模型确认**：默认「独立发版」模型——`dev`（rolling 集成沙盒）+ `main`（prod 发版源）。若探测到的分支不符（只有 `main`、用 `staging` / `beta` 等），用 `AskUserQuestion` 确认后写模板时替换。常见变体：

- **线性三段**（`develop → beta → main`，有独立 staging 冒烟）：`done` = 合 develop、`archived` = 合 beta 部署 staging。改 `tasks-index.sh` 段名文案 + Step 3 骨架协议为线性描述；hotfix 语义仍成立。
- **两段无 dev 服**（miniapp 类）：`archived` 段挂「已上传体验版待审核」。改 `emit_group` 段名文案即可。
- **单段 `main`**：生命周期简化为「已完成 → CHANGELOG」，删掉「待发布」段和 `emit_group archived` 那行；pre-commit 的「禁止直 commit main」校验也要删（单段模型就是在 main 上干活）。

**hooks 环境确认**：若 `hooks_path` 已被设置且不是 `.githooks`（如 husky 的 `.husky/_`），**不要抢**——用 `AskUserQuestion` 确认后，把 Step 5 两个 hook 的内容作为 skill-managed 块（`# BEGIN:init-agent-task-md` ↔ `# END:init-agent-task-md`）追加进现有 hooks 目录的同名文件；husky 项目追加进 `.husky/pre-commit` / `.husky/post-merge`。

---

## Step 1：三条路径

### Path A · 全新装

按顺序执行 Step 2 → 3 → 4 → 5 → 6 → 7 → 8。

### Path B · 迁移到 v3（v1 或 v2.x）

用 `AskUserQuestion` 明确告知用户 v3 是 **breaking**（文件名方案变了），会做的事：

- 每个任务文件按 `branch` 字段的 `/` 后缀改名：`T-042.md` → `T-<slug>.md`（如 `branch: feat/coupon-checkout` → `T-coupon-checkout.md`）；
- frontmatter：`id` 改成 `T-<slug>`；**删 `updated` 行**（改由 git log 派生）；加 `priority: 3`；`type: fix` 改成 `type: bugfix`；
- `trash scripts/tasks-status.sh`（v3 不再需要）；覆盖其余脚本；装 `.githooks`；
- TASKS.md 顶部「更新协议」换成 v3 文案（marker 外的「约束与决策」「踩坑与教训」原样不动）；
- CLAUDE.md / AGENTS.md 里旧的发布联动段替换为 v3「任务入口协议」marker 块。

用户确认后：

1. **v1 仓先拆文件**（v1 = monolith TASKS.md，无 docs/tasks/）：`cp "$TASKS_FILE" "$TASKS_FILE.v1.bak"`（别 `mv`），`mkdir -p docs/tasks`，用 Read 读全文，找每个含 `**T-XXX**` 的清单段，按所在章节推断 status（`进行中→doing / 待办→todo / 已完成→done / 归档→archived`），抽出 title / agent / branch / files / type，**直接用 v3 命名** Write 出 `docs/tasks/T-<slug>.md`（slug = branch 的 `/` 后缀；无 branch 时用 title slug 化）。
2. **v2 仓改名 + 改 frontmatter**：对每个 `docs/tasks/T-*.md`：
   - slug 取 `branch` 字段 `/` 后的部分；`branch` 为空时退化用旧 id 小写（`T-042.md` → `t-042` 不改名也行，唯一性不受影响，但建议补 branch 后重命名）；
   - 已被 git 跟踪的用 `git mv docs/tasks/T-042.md docs/tasks/T-<slug>.md`，未跟踪的用 `mv`；
   - Edit frontmatter：`id: T-<slug>`；删除 `updated:` 行；在 `type` 行后加 `priority: 3`；`type: fix` → `type: bugfix`。
   - 想保住原待办排序的话，按旧索引里 todo 段的顺序给 priority 依次填 1、2、3……（可选，默认全 3 也行）。
3. `trash scripts/tasks-status.sh`（存在时）。
4. 走 Step 3 重写 TASKS.md 顶部协议（保留手写段）→ Step 4 覆盖脚本 → Step 5 装 hook → Step 7 写入口协议 → 跑一次 `bash scripts/tasks-index.sh` 校验。
5. 让用户 review：v1 仓对照 `.v1.bak`，v2 仓 `git diff` 看改名与 frontmatter 变更；满意后由用户自行 `trash` 备份（skill 不代删）。

### Path C · 已装 v3，重装/升级

- 覆盖 3 个脚本（Step 4 最新版）+ 2 个 hook（Step 5 最新版）；
- **CLAUDE.md / AGENTS.md 里 `<!-- BEGIN:TASK-PROTOCOL ... --> ↔ <!-- END:TASK-PROTOCOL -->` 之间整块替换成 Step 7 最新版**（marker 块是 skill-managed，marker 外的内容一律不动）；
- TASKS.md 的索引 marker 语法变了就同步替换 marker 之间的注释文案；**手写段一律不动**；
- 跑 `bash scripts/tasks-index.sh` 重新生成一次索引。

---

## Step 2：建 `docs/tasks/` + 任务文件模板

```bash
mkdir -p docs/tasks
```

任务文件模板（`docs/tasks/T-<slug>.md`；用 `scripts/tasks-new.sh` 生成，或 agent 直接按此 Write——**v3 无编号无锁，直接 Write 是一等公民**，行尾注释可保留，索引脚本会剥掉）：

```markdown
---
id: T-<slug>            # 与文件名一致；slug = 分支名 / 后面的部分
title: <一句话讲清做什么、为什么>
status: todo            # todo | doing | done | archived
type: feat              # feat | bugfix | chore | hotfix
priority: 3             # 1 最高 … 5 最低；索引 todo/doing 段按此排序
agent: ""               # 开工时填 @agent-id，避免多 agent 抢同一个
branch: feat/<slug>     # 分支前缀与 type 同名：bugfix/ chore/ hotfix/
release: independent    # independent | batch-<name>——独立发版 or 随某批发
dev_verified: ""        # dev 联调通过日期 YYYY-MM-DD；hotfix 填 "skipped (hotfix)"
created: <YYYY-MM-DD>
files: ""               # 逗号分隔的影响文件通配，如 src/a.js, src/modules/b/**
---

## 描述

<一句话讲清做什么、为什么。bugfix 类补一句「命中场景 → 根因」。hotfix 类必须写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」。>

## 子任务

- [ ]

## 备注

<可选：设计取舍、遗留问题、下一步。>
```

**字段规则**：

- `id` 必须与文件名一致（都是 `T-<slug>`）。slug 只用 `[a-z0-9-]`。**同 slug 冲突是语义信号**：建文件前发现 `T-<slug>.md` 已存在，先读它——大概率另一个 agent 在做同一件事，该接手或换个真正不同的 slug，而不是绕过。
- `status` 是索引脚本唯一识别的分组依据。**流转 = 直接 Edit 这一行**（todo → doing → done → archived），改完随代码一起 commit 即可——索引由 pre-commit hook 自动重生成，"最近改动日期"由 git log 派生，**没有任何需要手工同步的伴生字段**。
- `priority`：1 最高、5 最低，缺省 3。索引里 todo/doing 段按它升序排（同级按文件名字典序），非默认值会渲染成 `P1`/`P2` 徽标。**调优先级就是改这个数字**，不用像 v2 那样受 ID 字典序绑架。
- `type` 影响两处：`tasks-release.sh` 归类到 CHANGELOG（feat→Added / bugfix|hotfix→Fixed / chore→Changed）；分支名前缀。
- `release`：`independent`（默认，单独发 tag）| `batch-<name>`（合车发版，索引行尾贴 `🚂`）。
- `dev_verified`：dev 联调通过日期，手工填；hotfix 填 `"skipped (hotfix)"`。
- `files` 是逗号分隔单行，索引原样渲染。项目可自行扩展扁平字段（如 `deps:`），索引脚本不识别的字段静默忽略。
- **没有 `updated` 字段**（v3 起废除）。别加回来——它只会重新制造"改 status 忘了改日期"的同步负担。

---

## Step 3：写 `docs/TASKS.md`

Path A / Path B 都从这个骨架写起（Path B 把老 TASKS.md 顶部项目说明和底部「约束与决策」「踩坑与教训」原样搬进对应位置）。`<项目名>` 与分支名按 Step 0 探测结果替换：

```markdown
---
project: <项目名>
updated: <YYYY-MM-DD>
---

# 进度 · <项目名>

> **更新协议（v3 · 无编号 + hook 自动化）**
> - **每个任务 = `docs/tasks/T-<slug>.md`**，文件名即 ID——无编号无锁，任何 worktree 里直接建。本文件 4 个状态段是索引视图，由 git hook（pre-commit / post-merge）自动重生成，一般无需手工跑 `scripts/tasks-index.sh`。
> - **入口协议**：用户报告的 bug / 提出的需求，先登记任务 + 切 `<type>/<slug>` 分支，再动代码（详见 CLAUDE.md / AGENTS.md「任务入口协议」；pre-commit hook 会校验）。登记：`bash scripts/tasks-new.sh <feat|bugfix|chore|hotfix> <slug> "<标题>" [priority]`，或直接按 `docs/tasks/` 现有文件的模板 Write。
> - **状态流转 = 直接改任务文件 frontmatter 的 `status`**，改完 commit：
>   1. `status: doing` — 开工，填 `agent` / `files`，切 `<type>/<slug>` 分支；
>   2. 分支 merge 到 `dev` 联调（不改 status；联调通过手工填 `dev_verified: <日期>`）；
>   3. dev 联调通过 → `status: done`；
>   4. 分支 PR 到 `main` 且 merge → `status: archived`；
>   5. 打 tag 部署 prod → `bash scripts/tasks-release.sh T-<slug>`（条目自动写进 `CHANGELOG.md` 的 Unreleased 段 + trash 任务文件 + 刷索引）；发版切号：`bash scripts/tasks-release.sh --cut <版本号>`。
> - **hotfix fast lane**：`tasks-new.sh hotfix <slug> "..."` → 从 `main` 切 `hotfix/<slug>` → 修 → PR 回 `main` → `status: archived` → `tasks-release.sh` 打 tag。跳过 dev，`dev_verified` 填 `"skipped (hotfix)"`；事后开 `chore/backport-hotfix-<slug>` 把 fix merge 回 dev。**任务描述必须写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」**，否则用 bugfix 走正常流程。
> - **dev 分支纪律**：dev 是 rolling 集成沙盒，允许被 `reset --hard main` 推倒重建；**禁止 dev → main**；**禁止基于 dev 拉分支**。
> - 待办排序看 `priority`（1 最高，缺省 3）；挑任务优先选 `files` 不重叠的，减少并行冲突。
> - 决策 / 踩坑不进任务文件，写到本文件底部「🧭 约束与决策」「⚠️ 踩坑与教训」（手写区，索引脚本不动）。
> - 新 clone 后跑一次 `git config core.hooksPath .githooks` 启用流程 hook。

<!-- BEGIN:TASKS-INDEX (auto — do not edit; run scripts/tasks-index.sh) -->

## 🔨 进行中

_（暂无。tasks-new.sh 登记；开工把任务文件 status 改成 doing。）_

## 📋 待办（priority 升序）

_（暂无。）_

## ✅ 已完成（dev 联调通过，待合 main 独立发版）

_（暂无。）_

## 🗄️ 待发布（已合 main，待打 tag / 部署 prod）

_（暂无。）_

<!-- END:TASKS-INDEX -->

---

## 🧭 约束与决策（只增不删）

_（格式：`- **D-N** (YYYY-MM-DD)：<决策> — 原因：<...>`）_

## ⚠️ 踩坑与教训

_（写这里的都是「已经付出过代价的教训」，不写空口猜想。格式：`<坑> → 根因：<...> → 结论：<...>`）_
```

**关键**：`<!-- BEGIN:TASKS-INDEX ... -->` 和 `<!-- END:TASKS-INDEX -->` 两行必须一字不差，索引脚本靠它们定位重写区间。

---

## Step 4：写三个脚本

```bash
mkdir -p scripts
```

### 4a · `scripts/tasks-index.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-index.sh
# skill-managed: init-agent-task-md v3.0.0
#
# 从 docs/tasks/T-*.md 生成 docs/TASKS.md 的索引段。
# 只重写 <!-- BEGIN:TASKS-INDEX --> 到 <!-- END:TASKS-INDEX --> 之间，
# 其余内容（更新协议 / 决策 / 踩坑）原样保留。
#
# v3：一般不需要人工跑——.githooks/pre-commit 与 post-merge 会自动跑。
# 排序：doing/todo 按 priority 升序（1 最高，缺省 3），同级按文件名；
#       done/archived 按最近改动降序（git log 派生——v3 已废除 updated 字段）。

set -euo pipefail

TASKS_DIR="${TASKS_DIR:-docs/tasks}"
INDEX_FILE="${INDEX_FILE:-docs/TASKS.md}"
BEGIN_MARK='<!-- BEGIN:TASKS-INDEX (auto — do not edit; run scripts/tasks-index.sh) -->'
END_MARK='<!-- END:TASKS-INDEX -->'

[ -d "$TASKS_DIR" ]  || { echo "tasks dir not found: $TASKS_DIR"  >&2; exit 1; }
[ -f "$INDEX_FILE" ] || { echo "index file not found: $INDEX_FILE" >&2; exit 1; }
grep -qF "$BEGIN_MARK" "$INDEX_FILE" || { echo "marker missing (BEGIN) in $INDEX_FILE" >&2; exit 1; }
grep -qF "$END_MARK"   "$INDEX_FILE" || { echo "marker missing (END) in $INDEX_FILE"   >&2; exit 1; }

get_field() {
  # 用法：get_field <file> <field>；剥行尾注释与首尾引号（模板可带 # 注释）
  awk -v f="$2" '
    BEGIN { inf = 0 }
    /^---[[:space:]]*$/ { if (inf) exit; inf = 1; next }
    inf && $0 ~ "^"f"[[:space:]]*:" {
      sub("^"f"[[:space:]]*:[[:space:]]*", "", $0)
      sub(/[[:space:]]+#.*$/, "", $0)
      gsub(/^"|"$/, "", $0)
      sub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$1"
}

# 任务文件最近改动日期：git 派生；尚未 commit 的新文件用今天
last_touched() {
  local d=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    d="$(git log -1 --format=%as -- "$1" 2>/dev/null || true)"
  fi
  [ -n "$d" ] || d="$(date +%Y-%m-%d)"
  printf '%s' "$d"
}

emit_group() {
  local heading="$1" want="$2" empty="$3" f rows=""
  printf '\n## %s\n\n' "$heading"
  for f in "$TASKS_DIR"/T-*.md; do
    [ -e "$f" ] || continue
    local status id title agent branch priority release_ files touched checkbox line key
    status="$(get_field "$f" status)"
    [ "$status" = "$want" ] || continue
    id="$(get_field "$f" id)"; [ -n "$id" ] || id="$(basename "$f" .md)"
    title="$(get_field "$f" title)"
    agent="$(get_field "$f" agent)"
    branch="$(get_field "$f" branch)"
    priority="$(get_field "$f" priority)"
    case "$priority" in [1-5]) ;; *) priority=3 ;; esac
    release_="$(get_field "$f" release)"
    files="$(get_field "$f" files)"
    touched="$(last_touched "$f")"
    case "$want" in done|archived) checkbox="[x]" ;; *) checkbox="[ ]" ;; esac
    line="- $checkbox **$id** · $title"
    # priority 仅非默认值时渲染徽标，避免行太长
    [ "$priority" != "3" ] && line="$line · P${priority}"
    [ -n "$agent" ]  && line="$line · \`$agent\`"
    [ -n "$branch" ] && line="$line · \`$branch\`"
    [ -n "$release_" ] && [ "$release_" != "independent" ] && line="$line · 🚂 \`$release_\`"
    [ -n "$files" ]  && line="$line · 影响文件: $files"
    case "$want" in done|archived) line="$line · $touched" ;; esac
    line="$line · [详情](tasks/$(basename "$f"))"
    case "$want" in
      doing|todo) key="p${priority}·$(basename "$f")" ;;
      *)          key="${touched}·$(basename "$f")" ;;
    esac
    rows="${rows}${key}"$'\t'"${line}"$'\n'
  done
  if [ -z "$rows" ]; then
    printf '_%s_\n' "$empty"
  else
    case "$want" in
      done|archived) printf '%s' "$rows" | sort -t$'\t' -k1,1r | cut -f2- ;;
      *)             printf '%s' "$rows" | sort -t$'\t' -k1,1  | cut -f2- ;;
    esac
  fi
}

tmp="$(mktemp)"
{
  awk -v mark="$BEGIN_MARK" '
    { print }
    index($0, mark) > 0 { exit }
  ' "$INDEX_FILE"

  emit_group "🔨 进行中"                                       "doing"    "（暂无。tasks-new.sh 登记；开工把任务文件 status 改成 doing。）"
  emit_group "📋 待办（priority 升序）"                        "todo"     "（暂无。）"
  emit_group "✅ 已完成（dev 联调通过，待合 main 独立发版）"    "done"     "（暂无。）"
  emit_group "🗄️ 待发布（已合 main，待打 tag / 部署 prod）"     "archived" "（暂无。）"

  printf '\n%s\n' "$END_MARK"

  awk -v mark="$END_MARK" '
    found { print; next }
    index($0, mark) > 0 { found = 1 }
  ' "$INDEX_FILE"
} > "$tmp"

mv "$tmp" "$INDEX_FILE"
echo "✅ 索引已更新: $INDEX_FILE"
```

写入后 `chmod +x scripts/tasks-index.sh`。

**分支模型变体**只改 `emit_group` 的段名文案（status 名字 doing/todo/done/archived 不动），例：线性三段 `done` 段用「develop 已合入，待发 staging」、miniapp 两段 `archived` 段用「已上传体验版（待审核发布）」；单段 main 直接删 `emit_group ... archived` 那行。

### 4b · `scripts/tasks-new.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-new.sh
# skill-managed: init-agent-task-md v3.0.0
#
# 用法：scripts/tasks-new.sh <feat|bugfix|chore|hotfix> <slug> [标题] [priority(1-5)]
#
# v3：文件名即 ID（T-<slug>.md），无编号无锁——任何 checkout / worktree 里都能
# 直接跑。同名冲突 = 两个 agent 在做同一件事：先读已有文件，别绕过它。
# 本脚本只是模板便利：agent 也可以直接按模板 Write docs/tasks/T-<slug>.md。
#
# type 决定分支前缀 + CHANGELOG 归类：
#   feat    → feat/<slug>     → Added
#   bugfix  → bugfix/<slug>   → Fixed
#   chore   → chore/<slug>    → Changed
#   hotfix  → hotfix/<slug>   → Fixed（fast lane：从 main 直切，跳过 dev 集成）

set -euo pipefail

type="${1:-}"
slug="${2:-}"
title="${3:-$slug}"
priority="${4:-3}"

case "$type" in
  feat|bugfix|chore|hotfix) ;;
  *) echo "用法：$0 <feat|bugfix|chore|hotfix> <slug> [标题] [priority(1-5)]" >&2; exit 1 ;;
esac
case "$slug" in
  ''|-*|*[!a-z0-9-]*) echo "slug 只能用 [a-z0-9-] 且不能以 - 开头：'$slug'" >&2; exit 1 ;;
esac
case "$priority" in
  [1-5]) ;;
  *) echo "priority 应为 1-5（1 最高）" >&2; exit 1 ;;
esac

TASKS_DIR="${TASKS_DIR:-docs/tasks}"
mkdir -p "$TASKS_DIR"

id="T-$slug"
file="$TASKS_DIR/$id.md"
if [ -e "$file" ]; then
  echo "✗ $file 已存在——可能另一个 agent 已登记同一件事。先读它再决定接手还是换 slug。" >&2
  exit 1
fi

today="$(date +%Y-%m-%d)"
branch="$type/$slug"

cat > "$file" <<EOF
---
id: $id
title: $title
status: todo
type: $type
priority: $priority
agent: ""
branch: $branch
release: independent
dev_verified: ""
created: $today
files: ""
---

## 描述

<一句话讲清做什么、为什么。bugfix 类补一句「命中场景 → 根因」。hotfix 类必须写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」。>

## 子任务

- [ ]

## 备注
EOF

echo "$file"
```

写入后 `chmod +x scripts/tasks-new.sh`。

### 4c · `scripts/tasks-release.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-release.sh
# skill-managed: init-agent-task-md v3.0.0
#
# 用法 1：scripts/tasks-release.sh <T-slug>[.md]
#   打 tag 部署 prod 后的收尾：把该任务条目**直接写进** CHANGELOG.md 的
#   ## [Unreleased] 段（按 type 归入 ### Added/Fixed/Changed，缺段自动建），
#   然后 trash 任务文件 + 刷新索引（worktree 里跳过索引）。
#   v3 与 v2 的区别：append 到 Unreleased 是确定性操作，不再打印片段让人手工
#   粘贴；需要人判断的只剩「切版本号」，见用法 2。
#
# 用法 2：scripts/tasks-release.sh --cut <version>
#   把 ## [Unreleased] 现有内容整体降为 ## [<version>] - <today>，
#   并在其上新建空的 ## [Unreleased] 段。

set -euo pipefail

TASKS_DIR="${TASKS_DIR:-docs/tasks}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
today="$(date +%Y-%m-%d)"

[ -f "$CHANGELOG" ] || { echo "找不到 $CHANGELOG" >&2; exit 1; }

# ── 用法 2：--cut <version> ──
if [ "${1:-}" = "--cut" ]; then
  version="${2:-}"
  [ -n "$version" ] || { echo "用法：$0 --cut <version>" >&2; exit 1; }
  grep -qF '## [Unreleased]' "$CHANGELOG" || { echo "$CHANGELOG 里没有 ## [Unreleased] 段" >&2; exit 1; }
  tmp="$(mktemp)"
  awk -v ver="$version" -v today="$today" '
    /^## \[Unreleased\]/ && !done { printf "## [Unreleased]\n\n## [%s] - %s\n", ver, today; done=1; next }
    { print }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
  echo "✔ 已切版本：## [${version}] - ${today}（新的空 Unreleased 段已就位）"
  exit 0
fi

# ── 用法 1：<T-slug> ──
id="${1:-}"
[ -n "$id" ] || { echo "用法：$0 <T-slug> | --cut <version>" >&2; exit 1; }
case "$id" in
  *.md)    file="$TASKS_DIR/$(basename "$id")" ;;
  T-*|t-*) file="$TASKS_DIR/T-${id#[Tt]-}.md" ;;
  *)       file="$TASKS_DIR/T-$id.md" ;;   # 容错：漏写 T- 前缀
esac
[ -f "$file" ] || { echo "任务文件不存在: $file" >&2; exit 1; }

get_field() {
  awk -v f="$1" '
    BEGIN { inf = 0 }
    /^---[[:space:]]*$/ { if (inf) exit; inf = 1; next }
    inf && $0 ~ "^"f"[[:space:]]*:" {
      sub("^"f"[[:space:]]*:[[:space:]]*", "", $0)
      sub(/[[:space:]]+#.*$/, "", $0)
      gsub(/^"|"$/, "", $0)
      sub(/[[:space:]]+$/, "", $0)
      print
      exit
    }
  ' "$file"
}

fid="$(get_field id)"; [ -n "$fid" ] || fid="$(basename "$file" .md)"
title="$(get_field title)"
type_="$(get_field type)"
branch="$(get_field branch)"
status_="$(get_field status)"

if [ "$status_" != "archived" ] && [ "$status_" != "done" ]; then
  printf '⚠ 任务状态是 "%s"，不是 archived/done。真的要发版并删除吗？(y/N) ' "$status_" >&2
  read -r ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "取消。" >&2; exit 1 ;;
  esac
fi

case "$type_" in
  feat)              section="Added"   ;;
  bugfix|hotfix|fix) section="Fixed"   ;;
  *)                 section="Changed" ;;
esac

entry="- **${fid}** · ${title}（\`${branch}\`）"

# ── 条目直接写进 CHANGELOG 的 Unreleased 段 ──
tmp="$(mktemp)"
awk -v sec="$section" -v entry="$entry" '
  BEGIN { inserted = 0; in_unrel = 0; unrel_seen = 0; skipblank = 0 }
  {
    if (skipblank) { skipblank = 0; if ($0 ~ /^[[:space:]]*$/) next }
  }
  /^## \[Unreleased\]/ { print; in_unrel = 1; unrel_seen = 1; next }
  /^## / {
    if (!inserted && in_unrel)    { printf "### %s\n\n%s\n\n", sec, entry; inserted = 1 }
    if (!inserted && !unrel_seen) { printf "## [Unreleased]\n\n### %s\n\n%s\n\n", sec, entry; inserted = 1; unrel_seen = 1 }
    in_unrel = 0; print; next
  }
  {
    if (in_unrel && !inserted && $0 == "### " sec) {
      print; print ""; print entry; inserted = 1; skipblank = 1; next
    }
    print
  }
  END {
    if (!inserted) {
      if (!unrel_seen) printf "\n## [Unreleased]\n"
      printf "\n### %s\n\n%s\n", sec, entry
    }
  }
' "$CHANGELOG" > "$tmp"
mv "$tmp" "$CHANGELOG"
echo "✔ 已写入 $CHANGELOG · [Unreleased] › ### ${section}：${entry}"

# ── trash 任务文件 ──
if command -v trash >/dev/null 2>&1; then
  trash "$file"
  echo "✔ 已 trash $file"
else
  echo "⚠ 未安装 trash 命令；请手动移除 $file 后再跑 scripts/tasks-index.sh" >&2
  exit 2
fi

# ── 刷新索引（worktree 是局部视图，跳过）──
case "$(git rev-parse --git-dir 2>/dev/null || echo .)" in
  */worktrees/*)
    echo "⚠ 当前在 git worktree 里，已跳过 tasks-index.sh；回主 checkout commit 时 pre-commit 会自动刷。" >&2 ;;
  *)
    [ -x scripts/tasks-index.sh ] && bash scripts/tasks-index.sh ;;
esac
```

写入后 `chmod +x scripts/tasks-release.sh`。

---

## Step 5：装 git hooks（v3 核心——自动化与纪律都在这）

```bash
mkdir -p .githooks
```

### 5a · `.githooks/pre-commit`

```bash
#!/usr/bin/env bash
# .githooks/pre-commit
# skill-managed: init-agent-task-md v3.0.0
#
# ① 流程纪律：feat/bugfix/hotfix 分支必须有对应任务文件；禁止直接 commit main。
# ② docs/tasks/ 有 staged 变更 → 自动重生成 docs/TASKS.md 并带进本次 commit。
# 逃生口：git commit --no-verify，或 TASKS_GUARD=off git commit ...

set -u

[ "${TASKS_GUARD:-on}" = "off" ] && exit 0

branch="$(git symbolic-ref --quiet --short HEAD || echo "")"

# ① 禁止直接 commit 到 main/master（merge commit 放行）
case "$branch" in
  main|master)
    if [ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ]; then
      echo "✗ 禁止直接 commit 到 $branch —— main 只通过 PR merge 前进。" >&2
      echo "  确有必要：git commit --no-verify" >&2
      exit 1
    fi
    ;;
esac

# ② feat/bugfix/hotfix 分支必须先登记任务（chore/* 是免登记 lane，不校验）
case "$branch" in
  feat/*|bugfix/*|hotfix/*)
    if ! grep -rqsE "^branch:[[:space:]]*${branch}[[:space:]]*$" docs/tasks/ 2>/dev/null; then
      echo "✗ 分支 ${branch} 在 docs/tasks/ 里没有对应任务文件（frontmatter branch: ${branch}）。" >&2
      echo "  先登记：bash scripts/tasks-new.sh ${branch%%/*} ${branch#*/} \"<一句话标题>\"" >&2
      echo "  trivial 改动（typo/注释/文档）请走 chore/* 分支；确要跳过：git commit --no-verify" >&2
      exit 1
    fi
    ;;
esac

# ③ docs/tasks/ 有 staged 变更 → 刷新索引并带上（worktree 是局部视图，跳过）
if ! git diff --cached --quiet -- docs/tasks/ 2>/dev/null; then
  case "$(git rev-parse --git-dir)" in
    */worktrees/*) : ;;
    *)
      if [ -x scripts/tasks-index.sh ]; then
        bash scripts/tasks-index.sh >/dev/null 2>&1 && git add docs/TASKS.md
      fi
      ;;
  esac
fi

exit 0
```

### 5b · `.githooks/post-merge`

```bash
#!/usr/bin/env bash
# .githooks/post-merge
# skill-managed: init-agent-task-md v3.0.0
#
# 主 checkout pull / merge 之后，若本次合入动了 docs/tasks/，自动刷新索引。
# 索引是纯派生视图：这里只改工作区不自动 commit——随下次 commit 带上即可。

set -u

case "$(git rev-parse --git-dir)" in */worktrees/*) exit 0 ;; esac
git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD 2>/dev/null | grep -q '^docs/tasks/' || exit 0
[ -x scripts/tasks-index.sh ] && bash scripts/tasks-index.sh >/dev/null 2>&1
git diff --quiet -- docs/TASKS.md 2>/dev/null || echo "ℹ docs/TASKS.md 索引已刷新（post-merge），随下次 commit 提交即可。"
exit 0
```

### 5c · 启用

```bash
chmod +x .githooks/pre-commit .githooks/post-merge
git config core.hooksPath .githooks
```

- `core.hooksPath` 是 **repo-local 配置**，worktree 共享（config 是全仓一份），但**新 clone 需要重新跑一次** `git config core.hooksPath .githooks`——这句已写进 Step 3 的更新协议和 Step 7 的入口协议，agent / 人都能看到。
- **已有 hooks 方案时不要抢**（Step 0 探测到 `hooks_path` 非空且非 `.githooks`，或 `husky=yes`）：把 5a/5b 的正文用 `# BEGIN:init-agent-task-md` ↔ `# END:init-agent-task-md` 包起来追加进现有 hooks 目录的 `pre-commit` / `post-merge`（不存在就创建），重跑 skill 时按 marker 替换该块。
- 单段 `main` 分支模型：删掉 5a 的 ①（禁止直 commit main）——单段模型就是在 main 上干活。

---

## Step 6：写入 CHANGELOG.md（不存在时）

```markdown
# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

条目来源：打 tag 部署 prod 时由 `scripts/tasks-release.sh` 从 [`docs/tasks/`](docs/tasks/)
自动写入 Unreleased 段；发版切号用 `scripts/tasks-release.sh --cut <版本号>`
（流程见 [`docs/TASKS.md`](docs/TASKS.md) 更新协议）。

## [Unreleased]
```

已存在 CHANGELOG.md 时不动内容；若缺 `## [Unreleased]` 段，建议补一个（`tasks-release.sh` 缺段时也会自动建，不补也能跑）。

---

## Step 7：写 CLAUDE.md / AGENTS.md「任务入口协议」（必装）

> v2 的对应步骤是可选的，这是 v3 修的核心问题之一：**agent 日常会话根本读不到 SKILL.md，规则必须常驻 always-on memory 文件，且写成「触发条件 → 动作」而不是机制说明书。**

目标文件：项目有 `AGENTS.md` 用 AGENTS.md（跨工具生效），否则用 `CLAUDE.md`；两者都没有就创建 `CLAUDE.md` 只放这一段并提示用户之后跑 `/init-agents-md` 补全约定层。追加以下 marker 块（重跑 skill 按 marker 整块替换；`dev`/`main` 按 Step 0 探测的分支模型替换）：

```markdown
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
```

另建议把 `@docs/TASKS.md` 加进 CLAUDE.md 的 import 列表（任务索引常驻上下文，详情按需 `Read docs/tasks/T-<slug>.md`）。

---

## Step 8：追加会话结束自动化（可选，需已装 init-session-notes）

仅当 Step 0 探测 `worker=exists` 且（`autoindex=absent` 或 `taskcheck=absent`）时，用 `AskUserQuestion` 询问是否安装。确认后**分块**追加到 `.claude/hooks/_summarize-worker.sh` 末尾——已装的块不重复追加。v3 里这层是**兜底**（hook 已覆盖日常刷新），价值在于 worktree 会话结束后主仓库索引的自愈 + 任务推进检测。

### 8a · 自动跑索引脚本（`autoindex=absent` 时）

```bash

# ── 任务索引自动刷新（由 init-agent-task-md v3 安装）──
if [ -x "$cwd/scripts/tasks-index.sh" ]; then
  ( cd "$cwd" && bash scripts/tasks-index.sh >>"$log" 2>&1 ) || true
fi
```

### 8b · 任务推进检测（`taskcheck=absent` 时）

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

若 `worker=none`（未装 init-session-notes）：跳过本步，报告里提示「想要会话结束兜底刷索引 + 推进检测，先跑 `/init-session-notes`，再回来重跑本 skill」。

---

## Step 9：输出初始化 / 迁移报告

**Path A（全新装）**：

```
✅ 任务管理层已初始化（v3.1.0 · 无编号 + hook 自动化）：

  • docs/tasks/              （新建，空目录）
  • docs/TASKS.md            （新建，含 marker 索引区）
  • scripts/tasks-index.sh   （新建，可执行；由 hook 调用，一般无需手工跑）
  • scripts/tasks-new.sh     （新建，可执行；模板便利，也可直接 Write 任务文件）
  • scripts/tasks-release.sh （新建，可执行；条目直写 CHANGELOG + --cut 切版本）
  • .githooks/pre-commit     （新建：分支↔任务校验 + 拦直 commit main + 自动刷索引）
  • .githooks/post-merge     （新建：pull/merge 后自动刷索引）
  • core.hooksPath           （已指向 .githooks；新 clone 需重跑一次 git config）
  • CHANGELOG.md             （[新建/已存在保留]）
  • 任务入口协议             （已写入 [CLAUDE.md/AGENTS.md] marker 块）
  • SessionEnd 兜底          （[已追加/未装 init-session-notes/用户跳过/已存在]）

登记第一个任务：bash scripts/tasks-new.sh feat my-first "登记第一个任务"
开工：Edit docs/tasks/T-my-first.md 的 status → doing，切 feat/my-first 分支
```

**Path B（v1/v2 → v3 迁移）**：

```
✅ 任务管理层已迁移到 v3.1.0（从 [v1/v2.x]）：

  • docs/tasks/T-<slug>.md   （N 个任务文件已按 branch 后缀改名 + 更新 frontmatter）
  • frontmatter 变更          （id 改 slug 形式；删 updated；加 priority: 3；type: fix → bugfix）
  • scripts/tasks-status.sh  （已 trash——v3 状态流转 = 直接 Edit status 字段）
  • scripts/tasks-index.sh / tasks-new.sh / tasks-release.sh（已覆盖到 v3）
  • .githooks/ + core.hooksPath（已装：入口校验 + 自动刷索引）
  • docs/TASKS.md            （顶部协议已换 v3 文案；手写段未动；索引已重新生成）
  • 任务入口协议             （已写入 [CLAUDE.md/AGENTS.md]，替换旧发布联动段）

请 review：
  1. git diff 看任务文件改名与 frontmatter 变更是否无缺漏
  2. [v1 仓] 对照 docs/TASKS.md.v1.bak，满意后自行 trash 备份
  3. 团队同步三件事：新分支必须先有任务文件（hook 会拦）、
     状态流转直接改 status 字段、新 clone 跑 git config core.hooksPath .githooks
```

**Path C（v3 重装/升级）**：

```
✅ 任务管理层已更新到 v3.1.0：

  • scripts/*.sh、.githooks/*（已覆盖到最新版）
  • docs/TASKS.md            （索引已重新生成；正文与手写段未动）

如无变化则说明该项目已是最新，无需操作。
```

---

## 注意事项

- **slug 冲突是语义信号，不是错误**：`tasks-new.sh`（或直接 Write）发现 `T-<slug>.md` 已存在时，先 Read 它——大概率另一个 agent 在做同一件事，该接手/协调，而不是换个近义 slug 绕过（那才是真正的重复劳动）。
- **不要把 `updated` 字段加回来**：v3 的"最近改动日期"由 `git log -1 --format=%as` 派生，加回手工字段只会重新制造同步负担。同理不要恢复 tasks-status.sh——status 流转就是一行 Edit。
- **worktree 全面解禁，但索引只在主 checkout 生成**：v3 里任何脚本在任何 worktree 都能跑（无锁无编号）；只有 `docs/TASKS.md` 的重生成会在 worktree 里自动跳过（局部视图不完整）。worktree 分支上的 commit **永远不带 TASKS.md 变更** → merge 无冲突；索引在主 checkout 的 pre-commit / post-merge / SessionEnd 三个时机自愈。worktree 里 TASKS.md 本地陈旧无妨——任务详情永远以 `docs/tasks/T-<slug>.md` 为准。
- **chore 是免登记 lane，不是逃生舱**：有行为变化的改动走 chore 分支绕过 pre-commit 校验是纪律问题，hook 拦不住语义。入口协议里已写明白名单边界（typo / 注释 / 文档 / ≤10 行无行为变化）。
- **hook 逃生口**：`git commit --no-verify` 或 `TASKS_GUARD=off`。留给"确实特殊"的场景，agent 不应默认使用——CLAUDE.md 入口协议没授权它。
- **不要绕过 marker 区手改 TASKS.md 的索引段**——下次 hook 跑索引就没了。想法/决策/踩坑写 marker **之外**（底部两段）。
- **hotfix 纪律**：fast lane 跳 dev 直切 main，任务描述必须写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」，写不出就回退 bugfix。事后开 `chore/backport-hotfix-<slug>` 合回 dev。
- **dev 分支纪律**：dev 是 rolling 沙盒，可被 `reset --hard main`；禁止 dev → main、禁止基于 dev 拉分支、禁止 cherry-pick dev 的 commit 回 main。
- **已有 husky 等 hooks 方案**：不设 `core.hooksPath`，把 hook 正文按 marker 块追加进现有 hook 文件（见 Step 5c）。
- **索引脚本的 get_field 会剥行尾 `#` 注释**：所以 agent 直接从 Step 2 模板 Write（带注释）也能被正确解析；但 title 里别写 ` #`（空格+井号会被当注释剥掉）。
- **迁移备份**：v1 迁移先 `cp` 出 `.v1.bak`，用户 review 满意后由用户手动 `trash`（**绝对禁止 `rm`**——用户级全局约定）。
- **v2 → v3 breaking 清单**（Path B 迁移覆盖，此处备查）：
  - 文件名 `T-XXX.md` → `T-<slug>.md`；`id` 字段同步；
  - 删 `updated` 字段；新增 `priority` 字段（缺省 3，索引对缺失文件也按 3 处理，**存量不补也兼容**）；
  - `tasks-status.sh` 删除；`tasks-new.sh` 去锁、参数变为 `<type> <slug> [标题] [priority]`；
  - `tasks-release.sh` 从"打印片段"改为"直写 CHANGELOG Unreleased 段"，新增 `--cut <version>`；
  - 新增 `.githooks/pre-commit`、`.githooks/post-merge` + `core.hooksPath`；
  - CLAUDE.md/AGENTS.md 入口协议从可选建议升级为必装 marker 块（`BEGIN:TASK-PROTOCOL`）。
- **绝对禁止 `rm`**：删除任何文件时用 `trash`（用户级全局约定）。
