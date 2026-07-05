---
name: init-agent-task-md
version: 2.3.0
description: |
  为项目初始化「任务管理层」，多 agent 并发写入无冲突：
  1. docs/tasks/T-XXX.md：每个任务一份独立文件（frontmatter + 子任务清单），
     并发 agent 各写各的物理文件，天然无写竞争。
  2. docs/TASKS.md：由 scripts/tasks-index.sh 按 marker 区自动生成的索引视图；
     `<!-- BEGIN:TASKS-INDEX -->` ↔ `<!-- END:TASKS-INDEX -->` 之外的内容
     （更新协议 / 约束与决策 / 踩坑与教训）由人手写，脚本不动。
  3. scripts/tasks-new.sh：原子分配下一个可用 T-XXX 编号（mkdir 锁），
     防止多 agent 同时登记撞号。支持 feat/bugfix/chore/hotfix 四种 type。
  4. scripts/tasks-status.sh：一步改任务状态 + 更新 updated + 自动跑 index，
     可选 --agent=@xxx 同步认领。
  5. scripts/tasks-release.sh：合 main 上线时用——打印 CHANGELOG 片段到 stdout
     + trash 任务文件 + 跑 index。CHANGELOG.md 由人/agent 手工 append。
  6. CHANGELOG.md：Keep a Changelog 骨架（不存在时创建）。
  7. 可选：把「自动跑索引脚本 + 任务推进检测」段追加进 init-session-notes 的
     _summarize-worker.sh，会话结束时自动刷新 TASKS.md 并标出本次推进的 T-XXX。

  幂等升级：重跑 skill 时按 scripts/tasks-index.sh 里的 skill-managed 版本号
  自动分流——旧版 v1（monolith TASKS.md）走迁移；已是 v2.x 只覆盖脚本文件。

  本 skill 只管「任务管理」：会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)，
  CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。
  使用：/init-agent-task-md；或当用户说「给项目装任务管理」「初始化 TASKS.md」
  「把 TASKS.md 拆成一任务一文件」时也命中本 skill。
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# Init Agent Task MD v2（任务管理层 · 拆文件版）

为项目装一套**多 agent 并发无冲突 + 与 Git 分支/部署联动**的任务管理：

- **每个任务 = 一个独立文件** `docs/tasks/T-XXX.md`（frontmatter 记状态 / 类型 / 分支 / 影响文件；正文写子任务清单）。并发 agent 各写各的物理文件，Write / Edit 不再抢同一个 `TASKS.md`。
- **`docs/TASKS.md` = 索引视图**，由 `scripts/tasks-index.sh` 按 marker 区自动生成，谁最后跑谁的版本就是最新——即使抢一下也无所谓，因为内容可再生。
- **`scripts/tasks-new.sh` = 原子登记**：用 `mkdir` 锁分配下一个可用 T-XXX，防止两个 agent 同一秒都拿到 T-006。支持 `feat|bugfix|chore` 三种 type，branch 前缀直接同名（`feat/` `bugfix/` `chore/`）。多 agent 并发登记时必须在主树跑，见文末「注意事项」。
- **`scripts/tasks-status.sh` = 状态流转**：一步改 `status` + 更新 `updated` + 自动跑 index，可选 `--agent=@xxx` 同步认领（`--agent=""` 清空）。省去手工编辑 frontmatter。
- **`scripts/tasks-release.sh` = 上线提炼**：合 `main` 上线 prod 时用——打印 CHANGELOG 片段到 stdout（Keep a Changelog 格式）+ `trash` 任务文件 + 跑 index。CHANGELOG.md 的实际编辑由人/agent 手工做（版本号 / 日期 / 分组增补需要判断，脚本不硬改）。
- 生命周期（默认「独立发版」模型）：dev 联调通过 → ✅ 已完成，PR 到 `main` 且 merge → 🗄️ 待发布，`tasks-release.sh` 打 tag 部署 prod → 提炼进 `CHANGELOG.md` 并从 `docs/tasks/` 删除。**dev 是 rolling 集成沙盒**（feature 分支 merge 进来联调，不流回 main），每个任务在 main 上独立打 tag 发版。**hotfix 跳 dev**：从 main 切 `hotfix/<slug>` → 修 → PR 回 main → tag，事后 backport 回 dev。

> ⚠️ 该 skill 只管任务管理层。会话归档 hook 归 [`init-session-notes`](../init-session-notes/SKILL.md)；CLAUDE.md / AGENTS.md 分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)。三者**完全独立**，可单装。

---

## Step 0：探测项目状态 + 已装版本

```bash
CURRENT_VERSION="2.3.0"

git rev-parse --git-dir 2>/dev/null >/dev/null && echo "git=yes" || echo "git=no"
git branch -a 2>/dev/null | grep -E 'develop|beta|main|master' | head -10

# 任务文档 & 目录
[ -d docs/tasks ] && echo "tasks_dir=exists" || echo "tasks_dir=none"
TASKS_FILE=""
for f in "docs/TASKS.md" "TASKS.md" "TODO.md" "docs/TODO.md"; do
  [ -f "$f" ] && TASKS_FILE="$f" && break
done
[ -n "$TASKS_FILE" ] && echo "tasks_file=$TASKS_FILE" || echo "tasks_file=none"

# 索引/新建脚本 + 版本号
INSTALLED_VERSION=""
if [ -f scripts/tasks-index.sh ]; then
  INSTALLED_VERSION="$(grep -oE 'skill-managed: init-agent-task-md v[0-9]+\.[0-9]+\.[0-9]+' scripts/tasks-index.sh | head -1 | awk -F'v' '{print $NF}')"
fi
echo "installed_version=${INSTALLED_VERSION:-none}"
echo "current_version=$CURRENT_VERSION"

# TASKS.md 中是否已有 v2 marker
if [ -n "$TASKS_FILE" ] && grep -qF 'BEGIN:TASKS-INDEX' "$TASKS_FILE" 2>/dev/null; then
  echo "marker=present"
else
  echo "marker=absent"
fi

# CHANGELOG 与 session-notes hook
[ -f CHANGELOG.md ] && echo "changelog=exists" || echo "changelog=new"
[ -f .claude/hooks/_summarize-worker.sh ] && echo "worker=exists" || echo "worker=none"
[ -f .claude/hooks/_summarize-worker.sh ] && grep -q '任务文档检查' .claude/hooks/_summarize-worker.sh && echo "taskcheck=installed" || echo "taskcheck=absent"
[ -f .claude/hooks/_summarize-worker.sh ] && grep -q 'tasks-index.sh' .claude/hooks/_summarize-worker.sh && echo "autoindex=installed" || echo "autoindex=absent"
```

**根据探测结果分流**（Step 1 会用到）：

| 状态 | 分类 | 该走哪条路径 |
| --- | --- | --- |
| `tasks_dir=none` 且 `tasks_file=none` | 全新装 | **Path A**：从零建 |
| `tasks_dir=none` 且 `tasks_file` 有内容且 `marker=absent` | v1 老版仓 | **Path B**：迁移到 v2（拆文件） |
| `tasks_dir=exists` 且 `installed_version=$CURRENT_VERSION` | 已是最新 | **Path C**：重装（只覆盖脚本，正文不动） |
| `tasks_dir=exists` 且 `installed_version < $CURRENT_VERSION`（或空） | v2 但脚本旧 | **Path C**：升级脚本文件；必要时提示重跑索引 |

**分支模型确认**：默认「独立发版」模型——`dev`（rolling 集成沙盒，也可叫 `develop` / `dev-integration`）+ `main`（prod 发版源）两段并行独立发版。每个 feature 分支既 merge 到 dev 联调，又独立 PR 到 main 打 tag 发版；dev 不流回 main，允许被 `reset --hard main` 推倒重建；hotfix 从 main 直切跳过 dev。若探测到的分支不符（如只有 `main`、用 `staging` 等），用 `AskUserQuestion` 确认后写模板时替换。

常见变体：
- **线性三段**（有独立 staging 环境要冒烟，如 `develop → beta → main`）：`done` = 合 develop、`archived` = 合 beta 部署 staging、`release` = 合 main。此时不适用「独立发版」文案，需要改 `tasks-index.sh` 段名 + Step 3 骨架的更新协议为线性描述；hotfix 语义仍成立（跳 develop / beta 直切 main）。
- **两段无 dev 服**（如 miniapp 类的 `develop → main`）：`archived` 段挂「已上传体验版待审核发布」这类中间态——改 `tasks-index.sh` 里 `emit_group` 的段名文案即可，不动 status 名字。
- **单段** `main`：把生命周期简化为「已完成 → CHANGELOG」两跳，删掉「待发布」段和索引脚本里对应的 `emit_group archived` 那行。

---

## Step 1：三条路径

### Path A · 全新装

按顺序执行 Step 2 → 3 → 4 → 5 → 6 → 7。

### Path B · 从 v1 迁移到 v2

用 `AskUserQuestion` 明确告知用户：

- 会新建 `docs/tasks/` 目录，把老 `TASKS.md` 里的每个 `T-XXX` 段拆成独立文件；
- 老 `TASKS.md` 会先另存为 `docs/TASKS.md.v1.bak`（`trash` 前的备份，用户满意后再 `trash`），然后重写为带 marker 区的新骨架；
- 顶部说明、底部「约束与决策」「踩坑与教训」原样保留。

用户确认后：

1. `cp "$TASKS_FILE" "$TASKS_FILE.v1.bak"`（别用 `mv`——万一模型识别错还能救）。
2. `mkdir -p docs/tasks`。
3. **读老 TASKS.md，逐条转换**：
   - 用 Read 读全文。
   - 找每个 `- [ ]` 或 `- [x]` 开头且包含 `**T-XXX**` 的段（连带下面的缩进子任务清单）。
   - 根据所在的一级章节推断 `status`：
     - `## 🔨 进行中` → `doing`
     - `## 📋 待办` → `todo`
     - `## ✅ 已完成` → `done`
     - `## 🗄️ 历史归档` → `archived`
   - 从段落里抽出 `title`（`·` 前一句）、`agent`（`@xxx`）、`branch`（`` `feat/xxx` `` / `` `bugfix/xxx` `` / `` `chore/xxx` ``）、`files`（「影响文件:」后到行尾）、`type`（branch 前缀 = type 本身：`feat` / `bugfix` / `chore`）。
   - 用 Write 创建 `docs/tasks/T-XXX.md`，用下面的模板填。子任务清单原样搬进正文 `## 子任务` 段。
   - `created` 尽量从 git 里查 branch 首次出现日期（`git log --diff-filter=A --follow --format=%ad --date=short -- docs/TASKS.md | tail -1` 兜底），`updated` 用今天。
4. 拆完之后，走 Step 3 重写 `docs/TASKS.md` 骨架（保留原顶部说明和底部手写段）；Step 4 写脚本；Step 6 跑一次 `bash scripts/tasks-index.sh` 校验。
5. 让用户 review `docs/TASKS.md`，与 `docs/TASKS.md.v1.bak` 对照没差错后由用户手动 `trash docs/TASKS.md.v1.bak`（skill 不代删）。

### Path C · 已装 v2，只升级脚本

- 直接覆盖 4 个脚本（Step 4 给的最新版本）：
  - `scripts/tasks-index.sh`
  - `scripts/tasks-new.sh`
  - `scripts/tasks-status.sh`（v2.1+ 新增，可能不存在于 v2.0 装机）
  - `scripts/tasks-release.sh`（同上）
- 若 TASKS.md 的 marker 区语法变了，同步替换 marker 之间的注释文案。
- v2.0 → v2.1 时，建议把 TASKS.md 顶部更新协议改成引用新脚本用法（见 Step 3 骨架），但**手写段一律不动**。
- 跑 `bash scripts/tasks-index.sh` 让索引重新生成一次。

---

## Step 2：建 `docs/tasks/` + 首个任务模板

```bash
mkdir -p docs/tasks
```

任务文件模板（存到 `docs/tasks/T-XXX.md`，Path A 时不需要预置任何 T-XXX；Path B 迁移时逐个 Write 出来）：

```markdown
---
id: T-XXX
title: <一句话讲清做什么、为什么>
status: todo            # todo | doing | done | archived
type: feat              # feat | bugfix | chore | hotfix
agent: ""               # 开工时填 @agent-id，避免多 agent 抢同一个
branch: feat/<slug>     # 分支前缀与 type 同名：bugfix/ chore/ hotfix/
release: independent    # independent | batch-<name>——独立发版 or 随某批发
dev_verified: ""        # dev 联调通过日期 YYYY-MM-DD；hotfix 填 "skipped (hotfix)"
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
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

- `id` 必须与文件名一致（都是 `T-XXX`）；由 `scripts/tasks-new.sh` 原子分配，不要手挑。
- `status` 是索引脚本唯一识别的分组依据。生命周期流转 = 跑 `scripts/tasks-status.sh T-XXX <new-status>`（自动改 status + 更新 updated + 跑 index）。
- `type` 影响两处：`tasks-release.sh` 归类到 CHANGELOG（feat→Added / bugfix|hotfix→Fixed / chore→Changed）；`tasks-new.sh` 生成的分支名前缀（`feat/` `bugfix/` `chore/` `hotfix/`）。索引脚本不识别 type，但会把 branch 渲染进索引，人肉眼能分辨。
- `release`：`independent` 表示单独发一 tag（默认），`batch-<name>` 表示与某批任务合车发版。索引脚本仅在非 `independent` 时在行尾贴 `🚂 batch-<name>` 提示。
- `dev_verified`：dev 联调通过日期（YYYY-MM-DD），任务分支 merge 到 dev 并联调通过后手工填。hotfix 走 fast lane 时填 `"skipped (hotfix)"` 表明有意跳过。索引脚本不 render 该字段。
- `files` 是**逗号分隔单行**，索引脚本会原样贴到 TASKS.md 索引。项目可自行扩展 `deps: T-003, T-004` 之类扁平字段，索引脚本不识别的字段会静默忽略。

---

## Step 3：写 `docs/TASKS.md`

**Path A 全新装、Path B 迁移** 都从这个骨架写起（Path B 迁移时把老 TASKS.md 顶部说明和底部「约束与决策」「踩坑与教训」段原样搬进对应位置）。`<项目名>` 与分支名按 Step 0 探测结果替换：

```markdown
---
project: <项目名>
updated: <YYYY-MM-DD>
---

# 进度 · <项目名>

> **更新协议（v2.3 · 独立发版模型）**
> - **每个任务 = `docs/tasks/T-XXX.md`**，本文件的 4 个状态段是它的索引视图，由 `scripts/tasks-index.sh` 生成。
> - **发布模型**：`dev` 是 rolling 集成沙盒（可脏、可 reset），`main` 是 prod 发版源。每个任务独立从 feat/bugfix 分支 PR 到 `main` 打 tag 发版，dev 不流回 main。
> - 新增任务：跑 `bash scripts/tasks-new.sh <feat|bugfix|chore|hotfix> <slug> "<一句话标题>"` → 得到 `docs/tasks/T-XXX.md`，填 `agent`、`files`、`release` 等字段。**不要手写 T-XXX 编号**，脚本用 mkdir 锁原子分配，防止多 agent 撞号。
> - 状态流转 = 跑 `bash scripts/tasks-status.sh T-XXX <todo|doing|done|archived> [--agent=@xxx]`（自动改 status + updated 并刷新索引；`--agent=""` 清空认领）：
>   1. `status: doing` — 开始动手；`--agent=@xxx` 同步认领；切 `feat/<slug>` 或 `bugfix/<slug>` 分支；
>   2. 分支 merge 到 `dev` 联调（**不改 status**，只在任务文件里手工填 `dev_verified: <日期>`）；
>   3. dev 联调通过 → `status: done`；
>   4. 分支 PR 到 `main` 且 merge → `status: archived`；
>   5. 打 tag 部署 prod → 跑 `bash scripts/tasks-release.sh T-XXX [版本号]`（打印 CHANGELOG 片段到 stdout + trash 任务文件 + 刷新索引），把片段粘贴到 `CHANGELOG.md`。
> - **hotfix fast lane**：`bash scripts/tasks-new.sh hotfix <slug> "..."` → 从 `main` 切 `hotfix/<slug>` → 修 → PR 回 `main` → `status: archived` → `tasks-release.sh` 打 tag 部署。跳过 dev 联调，`dev_verified` 填 `"skipped (hotfix)"`；事后开 `chore/backport-hotfix-<slug>` 把 fix merge 回 dev。**开 hotfix 必须在任务描述里写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」**，否则用 bugfix 走正常流程。
> - **dev 分支纪律**：dev 允许被 `reset --hard main` 推倒重建；**禁止 dev → main**（会把在途 feature 拖进 prod）；**禁止基于 dev 拉分支**（下一次 reset 会带走）。
> - 挑任务时优先选影响文件不重叠的，减少并行冲突。
> - 决策 / 踩坑不进任务文件，写到本文件底部「🧭 约束与决策」「⚠️ 踩坑与教训」（这两段是本文件手写区，索引脚本不会动）。

<!-- BEGIN:TASKS-INDEX (auto — do not edit; run scripts/tasks-index.sh) -->

## 🔨 进行中

_（暂无。用 scripts/tasks-new.sh 登记；开工后跑 scripts/tasks-status.sh T-XXX doing。）_

## 📋 待办（优先级从上到下）

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

## Step 4：写四个脚本

```bash
mkdir -p scripts
```

### 4a · `scripts/tasks-index.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-index.sh
# skill-managed: init-agent-task-md v2.3.0
#
# 从 docs/tasks/T-*.md 生成 docs/TASKS.md 的索引段。
# 只重写 <!-- BEGIN:TASKS-INDEX --> 到 <!-- END:TASKS-INDEX --> 之间，
# 其余内容（更新协议 / 决策 / 踩坑）原样保留。
#
# 多 agent 并发场景：任务文件互不冲突；索引由本脚本单点生成，谁最后跑就是最新。

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
  # 用法：get_field <file> <field>
  awk -v f="$2" '
    BEGIN { inf = 0 }
    /^---[[:space:]]*$/ { if (inf) exit; inf = 1; next }
    inf && $0 ~ "^"f"[[:space:]]*:" {
      sub("^"f"[[:space:]]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print
      exit
    }
  ' "$1"
}

emit_group() {
  local heading="$1" want="$2" empty="$3" any=0 f
  printf '\n## %s\n\n' "$heading"
  for f in $(ls "$TASKS_DIR"/T-*.md 2>/dev/null | sort); do
    [ -e "$f" ] || continue
    local status id title agent branch release_ files updated checkbox line
    status="$(get_field "$f" status)"
    [ "$status" = "$want" ] || continue
    id="$(get_field "$f" id)"; [ -n "$id" ] || id="$(basename "$f" .md)"
    title="$(get_field "$f" title)"
    agent="$(get_field "$f" agent)"
    branch="$(get_field "$f" branch)"
    release_="$(get_field "$f" release)"
    files="$(get_field "$f" files)"
    updated="$(get_field "$f" updated)"
    case "$want" in done|archived) checkbox="[x]" ;; *) checkbox="[ ]" ;; esac
    line="- $checkbox **$id** · $title"
    [ -n "$agent" ]  && line="$line · \`$agent\`"
    [ -n "$branch" ] && line="$line · \`$branch\`"
    # release 仅在非默认（非 independent、非空）时渲染，避免索引行太长
    [ -n "$release_" ] && [ "$release_" != "independent" ] && line="$line · 🚂 \`$release_\`"
    [ -n "$files" ]  && line="$line · 影响文件: $files"
    case "$want" in
      done|archived) [ -n "$updated" ] && line="$line · $updated" ;;
    esac
    line="$line · [详情](tasks/$(basename "$f"))"
    printf '%s\n' "$line"
    any=1
  done
  if [ "$any" -eq 0 ]; then
    printf '_%s_\n' "$empty"
  fi
}

tmp="$(mktemp)"
{
  # 复制 BEGIN 之前（含 BEGIN 行）
  awk -v mark="$BEGIN_MARK" '
    { print }
    index($0, mark) > 0 { exit }
  ' "$INDEX_FILE"

  emit_group "🔨 进行中"                                        "doing"    "（暂无。用 scripts/tasks-new.sh 登记；开工后跑 scripts/tasks-status.sh T-XXX doing。）"
  emit_group "📋 待办（优先级从上到下）"                        "todo"     "（暂无。）"
  emit_group "✅ 已完成（dev 联调通过，待合 main 独立发版）"     "done"     "（暂无。）"
  emit_group "🗄️ 待发布（已合 main，待打 tag / 部署 prod）"      "archived" "（暂无。）"

  printf '\n%s\n' "$END_MARK"

  # 复制 END 之后
  awk -v mark="$END_MARK" '
    found { print; next }
    index($0, mark) > 0 { found = 1 }
  ' "$INDEX_FILE"
} > "$tmp"

mv "$tmp" "$INDEX_FILE"
echo "✅ 索引已更新: $INDEX_FILE"
```

写入后 `chmod +x scripts/tasks-index.sh`。

**变体：无 dev 服的两段模型**（如 miniapp 类的 `develop → main`）——把 `emit_group` 的段名文案改成符合项目语义即可，`status` 名字（doing/todo/done/archived）不动。例如 miniapp 场景可改成：

```bash
  emit_group "✅ 已完成（develop 已合入，待上传体验版）"     "done"     "..."
  emit_group "🗄️ 已上传体验版（待审核通过发布正式版）"      "archived" "..."
```

**变体：线性三段（`develop → beta → main`）**——`done` = 合 develop、`archived` = 合 beta 部署 staging：

```bash
  emit_group "✅ 已完成（develop 已合入，待发 staging）"     "done"     "..."
  emit_group "🗄️ 历史归档（已部署 staging，待上线 prod）"    "archived" "..."
```

### 4b · `scripts/tasks-new.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-new.sh
# skill-managed: init-agent-task-md v2.3.0
#
# 用法：scripts/tasks-new.sh <feat|bugfix|chore|hotfix> <slug> [标题]
# 原子分配下一个可用的 T-XXX 编号（mkdir 锁），
# 创建 docs/tasks/T-XXX.md 骨架，输出该路径。
#
# type 决定分支前缀 + CHANGELOG 归类：
#   feat    → feat/<slug>     → Added
#   bugfix  → bugfix/<slug>   → Fixed
#   chore   → chore/<slug>    → Changed
#   hotfix  → hotfix/<slug>   → Fixed（fast lane：从 main 直切，跳过 dev 集成）
#
# ⚠ 多 agent 并发登记时必须在主树（git rev-parse --show-toplevel 的主 checkout）跑，
#    不能在各自 worktree 里各跑一份——锁 key = `pwd | shasum`，worktree 里 pwd 不同
#    会让锁失效；且 worktree 之间 docs/tasks/ 视图独立，扫到的 last 编号相同 → 撞号。
#    正确做法：主树跑本脚本拿到 T-XXX.md，再 mv 到各 worktree 里 commit。

set -euo pipefail

type="${1:-}"
slug="${2:-}"
title="${3:-$slug}"

case "$type" in
  feat|bugfix|chore|hotfix) ;;
  *) echo "用法：$0 <feat|bugfix|chore|hotfix> <slug> [标题]" >&2; exit 1 ;;
esac
[ -n "$slug" ] || { echo "缺 slug" >&2; exit 1; }

TASKS_DIR="${TASKS_DIR:-docs/tasks}"
mkdir -p "$TASKS_DIR"

# worktree 检测：如果当前不是主 checkout，警告一下——多 agent 场景会撞号。
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  gitdir="$(git rev-parse --git-dir)"
  case "$gitdir" in
    */worktrees/*)
      echo "⚠ 当前在 git worktree 里跑 tasks-new.sh。单 agent 场景 OK；" >&2
      echo "  多 agent 并发登记时请回主树（git rev-parse --show-toplevel 的主 checkout）跑，避免撞号。" >&2
      ;;
  esac
fi

repo_key="$(pwd | shasum 2>/dev/null | cut -c1-12)"
[ -n "$repo_key" ] || repo_key="$$"
LOCK="${TMPDIR:-/tmp}/tasks-new.${repo_key}.lock"

i=0
until mkdir "$LOCK" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && { echo "锁等待超时: $LOCK（若确认无并发，rmdir 该目录后重试）" >&2; exit 1; }
  sleep 0.1
done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

last=0
for f in "$TASKS_DIR"/T-*.md; do
  [ -e "$f" ] || continue
  n="$(basename "$f" .md | sed 's/^T-0*//')"
  [ -n "$n" ] || n=0
  if [ "$n" -gt "$last" ] 2>/dev/null; then last="$n"; fi
done
next=$((last + 1))
id="$(printf 'T-%03d' "$next")"
file="$TASKS_DIR/$id.md"

today="$(date +%Y-%m-%d)"
# type = 分支前缀（feat / bugfix / chore）
branch="$type/$slug"

cat > "$file" <<EOF
---
id: $id
title: $title
status: todo
type: $type
agent: ""
branch: $branch
release: independent
dev_verified: ""
created: $today
updated: $today
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

### 4c · `scripts/tasks-status.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-status.sh
# skill-managed: init-agent-task-md v2.3.0
#
# 用法：scripts/tasks-status.sh <T-XXX|T-XXX.md> <todo|doing|done|archived> [--agent=@xxx]
# 改任务文件的 status + updated + （可选）agent，然后跑 tasks-index.sh 刷新索引。
# 传 --agent="" 即可清空 agent 字段（把 status 改回 todo 时常用）。
#
# ⚠ 在 git worktree 里跑时会**自动跳过** tasks-index.sh——worktree 的 docs/tasks/
#    是局部视图（看不到其他 branch 的 T-XXX 文件），生成的索引不完整，commit 后会
#    覆盖 develop 上完整索引。索引由主仓库单点生成（agent pull develop 后手动跑
#    tasks-index.sh，或 SessionEnd hook 自动跑）。任务文件的 status/updated 字段
#    仍会正常更新——只是不重写 docs/TASKS.md。

set -euo pipefail

id="${1:-}"
new_status="${2:-}"
shift 2 2>/dev/null || true

TASKS_DIR="${TASKS_DIR:-docs/tasks}"

# 解析可选 --agent=<值>（传 --agent="" 即可清空 agent 字段）
new_agent=""
agent_flag=0
for arg in "$@"; do
  case "$arg" in
    --agent=*) new_agent="${arg#--agent=}"; agent_flag=1 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

case "$new_status" in
  todo|doing|done|archived) ;;
  *) echo "用法：$0 <T-XXX> <todo|doing|done|archived> [--agent=@xxx]" >&2; exit 1 ;;
esac

[ -n "$id" ] || { echo "缺 T-XXX" >&2; exit 1; }
case "$id" in
  *.md)     file="$TASKS_DIR/$(basename "$id")" ;;
  T-*|t-*)
    id_upper="$(echo "$id" | tr '[:lower:]' '[:upper:]')"
    file="$TASKS_DIR/${id_upper}.md" ;;
  *) echo "无效 id: $id（应为 T-XXX 或 T-XXX.md）" >&2; exit 1 ;;
esac

[ -f "$file" ] || { echo "任务文件不存在: $file" >&2; exit 1; }

today="$(date +%Y-%m-%d)"

tmp="$(mktemp)"
awk -v ns="$new_status" -v today="$today" -v na="$new_agent" -v af="$agent_flag" '
  BEGIN { inf = 0 }
  /^---[[:space:]]*$/ { print; inf = (inf ? 0 : 1); next }
  inf && /^status[[:space:]]*:/ { print "status: " ns; next }
  inf && /^updated[[:space:]]*:/ { print "updated: " today; next }
  inf && af == "1" && /^agent[[:space:]]*:/ { print "agent: \"" na "\""; next }
  { print }
' "$file" > "$tmp"

mv "$tmp" "$file"

# worktree 检测：worktree 里跑不刷索引（视图不完整会覆盖 develop 上完整索引）
in_worktree=0
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  gitdir="$(git rev-parse --git-dir)"
  case "$gitdir" in
    */worktrees/*) in_worktree=1 ;;
  esac
fi

if [ "$in_worktree" = "1" ]; then
  echo "⚠ 当前在 git worktree 里，已跳过 tasks-index.sh。" >&2
  echo "  索引由主仓库单点生成：PR merge 后回主仓库 pull，然后跑 bash scripts/tasks-index.sh。" >&2
elif [ -x "scripts/tasks-index.sh" ]; then
  bash scripts/tasks-index.sh
fi

msg="✔ $file → status: $new_status, updated: $today"
[ "$agent_flag" = "1" ] && msg="$msg, agent: \"$new_agent\""
echo "$msg"
```

写入后 `chmod +x scripts/tasks-status.sh`。

### 4d · `scripts/tasks-release.sh`

```bash
#!/usr/bin/env bash
# scripts/tasks-release.sh
# skill-managed: init-agent-task-md v2.3.0
#
# 用法：scripts/tasks-release.sh <T-XXX|T-XXX.md> [<version>]
# 用途：合 main 上线 prod 后，把归档任务提炼进 CHANGELOG 新版本段。
#
# 本脚本做三件事：
#   1. 打印可粘贴到 CHANGELOG.md 的片段到 stdout（Keep a Changelog 格式）；
#   2. trash 该任务文件（要求已装 trash 命令；未装则跳过 + 提示）；
#   3. 跑 scripts/tasks-index.sh 刷新索引（仅主仓库，worktree 里跳过）。
#
# CHANGELOG.md 的实际编辑由人/agent 手工做——版本号 / 日期 / 分组增补
# 都可能需要判断，脚本不硬改 CHANGELOG 避免误覆盖。
#
# ⚠ 推荐在主仓库（主 checkout）跑本脚本——通常发版就是切到 main 走流程。
#    若在 worktree 里跑，会自动跳过 tasks-index.sh（视图不完整会覆盖 develop 索引），
#    trash 和 stdout 打印仍正常执行。

set -euo pipefail

id="${1:-}"
version="${2:-}"

TASKS_DIR="${TASKS_DIR:-docs/tasks}"

[ -n "$id" ] || { echo "用法：$0 <T-XXX> [<version>]" >&2; exit 1; }

case "$id" in
  *.md)     file="$TASKS_DIR/$(basename "$id")" ;;
  T-*|t-*)
    id_upper="$(echo "$id" | tr '[:lower:]' '[:upper:]')"
    file="$TASKS_DIR/${id_upper}.md" ;;
  *) echo "无效 id: $id" >&2; exit 1 ;;
esac

[ -f "$file" ] || { echo "任务文件不存在: $file" >&2; exit 1; }

get_field() {
  awk -v f="$1" '
    BEGIN { inf = 0 }
    /^---[[:space:]]*$/ { if (inf) exit; inf = 1; next }
    inf && $0 ~ "^"f"[[:space:]]*:" {
      sub("^"f"[[:space:]]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print
      exit
    }
  ' "$file"
}

fid="$(get_field id)"
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
  feat)                     section="Added"   ;;
  bugfix|hotfix|fix)        section="Fixed"   ;;  # 存量 v2.1 任务里 type: fix 也识别一下
  chore)                    section="Changed" ;;
  *)                        section="Changed" ;;
esac

today="$(date +%Y-%m-%d)"

# ── CHANGELOG 片段 → stdout ──
# 注意：变量引用一律用 ${...} 显式界定——中文全角括号等 non-ASCII 字符
# 紧跟变量名时，某些 locale 下 bash 会把它吞进变量名致 unbound variable。
{
  echo "─────── 粘贴以下到 CHANGELOG.md ───────"
  echo ""
  if [ -n "$version" ]; then
    echo "## [$version] - $today"
    echo ""
  fi
  echo "### $section"
  echo ""
  echo "- **${fid}** · ${title}（\`${branch}\`）"
  echo ""
  echo "───────────────────────────────────────"
} >&1

# ── trash 任务文件 ──
if command -v trash >/dev/null 2>&1; then
  trash "$file"
  echo "✔ 已 trash $file"
else
  echo "⚠ 未安装 trash 命令；请手动移除 $file 后再跑 scripts/tasks-index.sh" >&2
  exit 2
fi

# ── 刷新索引（worktree 里跳过）──
in_worktree=0
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  gitdir="$(git rev-parse --git-dir)"
  case "$gitdir" in
    */worktrees/*) in_worktree=1 ;;
  esac
fi

if [ "$in_worktree" = "1" ]; then
  echo "⚠ 当前在 git worktree 里，已跳过 tasks-index.sh。" >&2
  echo "  请回主仓库跑 bash scripts/tasks-index.sh 刷新完整索引。" >&2
  echo "✔ 请把上面片段追加到 CHANGELOG.md（版本号 / 日期自定）。"
elif [ -x "scripts/tasks-index.sh" ]; then
  bash scripts/tasks-index.sh
  echo "✔ 索引已刷新。请把上面片段追加到 CHANGELOG.md（版本号 / 日期自定）。"
else
  echo "✔ 请把上面片段追加到 CHANGELOG.md（版本号 / 日期自定）。"
fi
```

写入后 `chmod +x scripts/tasks-release.sh`。

---

## Step 5：写入 CHANGELOG.md（不存在时）

```markdown
# Changelog

本项目所有重要变更记录于此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

条目来源：合 `main` 上线 prod 时，由 [`docs/tasks/`](docs/tasks/) 中随本次上线的任务
（`status: archived`）经 `scripts/tasks-release.sh` 提炼而来（流程见 [`docs/TASKS.md`](docs/TASKS.md) 更新协议）。

## [Unreleased]
```

已存在 CHANGELOG.md 时不动内容，只建议用户在文件头补一行「条目来源」说明。

---

## Step 6：把生命周期约定挂进 CLAUDE.md（可选）

若项目有 `CLAUDE.md`（或 `AGENTS.md`），用 `AskUserQuestion` 询问是否补充发布规范联动。要点：

- **新任务必走脚本**：`bash scripts/tasks-new.sh <feat|bugfix|chore> <slug> "<标题>"` 拿 T-XXX，禁止手写 T-XXX 编号或直接 Write `docs/tasks/T-XXX.md`（会撞号）。
- **开工时**：`bash scripts/tasks-status.sh T-XXX doing --agent=@<你的 id>`，然后补 `files` 字段（这是 tasks-status.sh 不会改的字段，仍需 Edit 任务文件）。
- **分支 merge 到 `dev` 联调**：不改 status，在任务文件里手工填 `dev_verified: <日期>`。
- **dev 联调通过**：`bash scripts/tasks-status.sh T-XXX done`。
- **分支 PR 到 `main` 且 merge**：`bash scripts/tasks-status.sh T-XXX archived`。
- **打 tag 部署 prod**：`bash scripts/tasks-release.sh T-XXX <版本号>` → 复制打印出的 CHANGELOG 片段到 `CHANGELOG.md` 相应版本段。
- **hotfix fast lane**：`bash scripts/tasks-new.sh hotfix <slug> "..."` → 从 `main` 切 `hotfix/<slug>` → 修 → PR 回 `main` → `tasks-status.sh T-XXX archived` → `tasks-release.sh` 打 tag。跳过 dev，`dev_verified` 填 `"skipped (hotfix)"`；事后开 `chore/backport-hotfix-<slug>` 把 fix merge 回 dev。**开 hotfix 必须在任务描述里写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」**，否则回退到 bugfix 走正常流程。
- **dev 分支纪律**：dev 是 rolling 集成沙盒，允许被 `reset --hard main` 推倒重建；**禁止 dev → main**（会把在途 feature 拖进 prod）；**禁止基于 dev 拉分支**。
- **主仓库 `git pull` develop 后跑一次 `bash scripts/tasks-index.sh`**：worktree 里的 `tasks-status.sh` / `tasks-release.sh` 会跳过索引刷新（视图不完整），索引由主仓库单点自愈。装了 init-session-notes 的话 SessionEnd hook 会代跑，人工兜底一次也无妨。
- 建议把 `@docs/TASKS.md` 加进 CLAUDE.md 的 import 列表，让每次会话自动加载任务索引；具体任务详情按需 `Read docs/tasks/T-XXX.md`，避免所有任务全文进 always-on 上下文。

---

## Step 7：追加会话结束自动化（可选，需已装 init-session-notes）

仅当 Step 0 探测 `worker=exists` 且（`autoindex=absent` 或 `taskcheck=absent`）时，用 `AskUserQuestion` 询问是否安装。确认后**分块**追加到 `.claude/hooks/_summarize-worker.sh` 末尾——已装的块不重复追加：

### 7a · 自动跑索引脚本（`autoindex=absent` 时）

```bash

# ── 任务索引自动刷新（由 init-agent-task-md v2 安装）──
if [ -x "$cwd/scripts/tasks-index.sh" ]; then
  ( cd "$cwd" && bash scripts/tasks-index.sh >>"$log" 2>&1 ) || true
fi
```

### 7b · 任务推进检测（`taskcheck=absent` 时）

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

若 `worker=none`（未装 init-session-notes）：跳过本步，报告里提示「想要会话结束自动刷索引 + 推进检测，先跑 `/init-session-notes`，再回来重跑本 skill」。

---

## Step 8：输出初始化 / 升级报告

**Path A（全新装）**：

```
✅ 任务管理层已初始化（v2.3.0 · 拆文件版）：

  • docs/tasks/              （新建，空目录）
  • docs/TASKS.md            （新建，含 marker 索引区）
  • scripts/tasks-index.sh   （新建，可执行）
  • scripts/tasks-new.sh     （新建，可执行）
  • scripts/tasks-status.sh  （新建，可执行）
  • scripts/tasks-release.sh （新建，可执行）
  • CHANGELOG.md             （[新建/已存在保留]）
  • CLAUDE.md 发布联动约定   （[已补充/用户跳过/无 CLAUDE.md]）
  • SessionEnd 联动          （[已追加索引自动刷新+推进检测/未装 init-session-notes/用户跳过/已存在]）

新增任务：bash scripts/tasks-new.sh feat my-first "登记第一个任务"
开工认领：bash scripts/tasks-status.sh T-001 doing --agent=@you
刷新索引：bash scripts/tasks-index.sh
```

**Path B（v1→v2 迁移）**：

```
✅ 任务管理层已从 v1 升级到 v2.3.0：

  • docs/tasks/              （新建，已迁入 N 个 T-XXX 文件）
  • docs/TASKS.md            （已重写为 marker 索引骨架 + 保留原顶部说明 + 底部决策/踩坑段）
  • docs/TASKS.md.v1.bak     （旧版备份，请 review 后自行 trash）
  • scripts/tasks-index.sh   （新建，可执行）
  • scripts/tasks-new.sh     （新建，可执行）
  • scripts/tasks-status.sh  （新建，可执行）
  • scripts/tasks-release.sh （新建，可执行）
  • CHANGELOG.md             （[新建/已存在保留]）
  • CLAUDE.md 发布联动约定   （[已更新为 v2 流程/用户跳过/无 CLAUDE.md]）
  • SessionEnd 联动          （[已追加/未装 init-session-notes/用户跳过/已存在]）

请 review：
  1. diff docs/TASKS.md.v1.bak <(bash scripts/tasks-index.sh && cat docs/TASKS.md)
  2. 抽查几个 docs/tasks/T-XXX.md，确认迁移无缺漏
  3. 满意后 trash docs/TASKS.md.v1.bak
```

**Path C（v2 升级/重装）**：

```
✅ 任务管理层已升级到 v2.3.0（从 v<INSTALLED_VERSION>）：

  • scripts/tasks-index.sh   （已覆盖到最新版；新增 release 字段渲染）
  • scripts/tasks-new.sh     （已覆盖到最新版；新增 hotfix 类型 + release/dev_verified 模板字段）
  • scripts/tasks-status.sh  （[新增/已覆盖到最新版]）
  • scripts/tasks-release.sh （[新增/已覆盖到最新版]；bugfix|hotfix 都归 Fixed）
  • docs/TASKS.md            （marker 区段名文案已同步为「独立发版」语义；正文与手写段未动）
  • 已重新生成一次索引

⚠ v2.2 → v2.3 是**生命周期语义**变更（脚本行为不变，status 字段值不变）：
  • done   语义：合 develop → **dev 联调通过**
  • archived 语义：合 beta 部署 dev 服 → **已合 main 待打 tag / 部署 prod**
  • 新增 hotfix type + release/dev_verified 字段（存量任务无需迁移，向后兼容）
  请 review docs/TASKS.md 顶部的「更新协议」是否想同步换成新版文案（在手写区，Path C 不动），
  并口头告知团队新的分支纪律（dev 是 rolling 沙盒 / 每 feat 独立 PR 到 main / hotfix 跳 dev 直切 main）。

如无变化则说明该项目已是最新，无需操作。
```

---

## 注意事项

- **绝对不要手写 T-XXX 编号**——用 `scripts/tasks-new.sh` 分配。手写会撞号，撞号后再改就是**同一物理文件**的写竞争，回到 v1 的问题。
- **多 agent 并发登记必须在主树（主 checkout）跑 `tasks-new.sh`，不能在各自 worktree 里各跑一份**——`tasks-new.sh` 的锁是 `mkdir "$TMPDIR/tasks-new.$(pwd | shasum | cut -c1-12).lock"`：
  - **锁 key 绑定 `pwd`**：主树和每个 worktree 的绝对路径不同 → 锁 key 不同 → 两个 agent 同时 `mkdir` 都成功，锁形同虚设。
  - **`docs/tasks/` 视图独立**：每个 worktree 有自己的 working tree，从同一分支切出且都没登记新任务时，各自扫描到的 last 编号相同 → 分到相同的 T-XXX → PR merge 时打架或静默覆盖。
  - **正确做法**：所有 agent 到主树目录跑 `bash scripts/tasks-new.sh <feat|bugfix|chore> <slug> "<标题>"`，拿到的 `docs/tasks/T-XXX.md`（untracked in 主树）用 `mv` 搬到各自 worktree 去 commit。主树 develop 分支不落任何 T-XXX commit。
  - **单 agent 场景无此坑**——直接在 worktree 里跑 `tasks-new.sh` 也 OK。脚本会检测 worktree 环境并打 stderr 警告，不阻断执行。
- **`docs/TASKS.md` 索引由主仓库单点生成**——worktree 里跑 `tasks-status.sh` / `tasks-release.sh` 会**自动跳过** `tasks-index.sh`（因为 worktree 的 `docs/tasks/` 是局部视图，看不到其他 branch 的 T-XXX 文件，生成的索引会覆盖 develop 上完整视图）。任务文件的 `status` / `updated` / `agent` 字段仍会正常更新，只是不重写 `docs/TASKS.md`。索引在两个时机自愈：
  1. **agent PR merge 回 develop 后**：主仓库 `git pull` → 立即跑 `bash scripts/tasks-index.sh`（这一步建议写进 CLAUDE.md 的日常规范）。
  2. **SessionEnd hook**：若装了 [`init-session-notes`](../init-session-notes/SKILL.md) 且启用了「自动跑索引脚本」段（Step 7a），会话结束时自动在项目根（主仓库路径）跑 `tasks-index.sh`。
  worktree 里的 `docs/TASKS.md` 本地陈旧不影响 agent 干活——索引是纯衍生视图，看任务详情永远从 `docs/tasks/T-XXX.md` 读。
- **状态流转优先走 `tasks-status.sh`**——不要手工 Edit 任务文件的 `status` 字段，因为脚本会同步更新 `updated` 并自动跑 index，手工改容易漏这两步。仅 `files` / `description` / `子任务清单` 这类内容型字段才手工 Edit 任务文件。
- **合 main 上线走 `tasks-release.sh`**——不要手工 `trash` 任务文件 + 手写 CHANGELOG，脚本能保证「CHANGELOG 片段格式一致 + 文件真删 + 索引同步刷新」原子完成（虽然 CHANGELOG 的最终 append 仍是手工，但至少格式模板从脚本 stdout 复制不会漏字段）。
- **不要绕过 marker 区手改 TASKS.md 的索引段**——你写的内容下次跑索引脚本就没了。要写想法/决策/踩坑，写在 marker **之外**（底部两段）。
- **迁移时先 `cp` 备份再改 TASKS.md**：`cp docs/TASKS.md docs/TASKS.md.v1.bak`，别用 `mv`。用户 review 满意才由用户手动 `trash`（**绝对禁止 `rm`**——用户级全局约定）。
- **索引脚本按 `id` 字典序排 T-XXX**：默认从 001 起递增，索引里也按此顺序显示。想手工调优先级顺序时改任务文件的 `id` 是错的（要改就是全局重编号）；正确做法是**开一批新任务时按你想要的顺序 tasks-new**，或在正文里手写别名说明。
- **awk 前缀识别的章节标题写死在 worker 里**：如果改了 TASKS.md 的一级章节命名，同步改 `_summarize-worker.sh` 的正则。
- **变量引用用 `${...}` 界定**：脚本里凡是变量后紧跟中文全角括号（`（`）等 non-ASCII 字符的地方，一律写 `${var}` 而非 `$var`——某些 locale 下 bash 会把 non-ASCII 字节吞进变量名致 `unbound variable`。tasks-release.sh 里已按此约定。
- **Path C 的版本比较**：SKILL.md 声明 `CURRENT_VERSION="2.3.0"`；升级时若发现 `installed_version != CURRENT_VERSION`，直接覆盖脚本 + 重跑 index 即可。
  - v2.0 → v2.1：新增 `tasks-status.sh` / `tasks-release.sh` + `tasks-new.sh` 支持 chore。兼容旧任务文件。
  - **v2.1 → v2.2（breaking + worktree 感知）**：
    - **breaking**：`tasks-new.sh` 的 type 入参从 `feat|fix|chore` 改成 `feat|bugfix|chore`，脚本不再接受 `fix`。存量任务文件里 `type: fix` 建议一次性 sed 换成 `type: bugfix`：`grep -rlE '^type: fix$' docs/tasks/ | xargs sed -i.bak 's/^type: fix$/type: bugfix/'`（macOS 用 `sed -i ''`）。不换也不会立即出错——`tasks-release.sh` 里 `bugfix|fix` 一起识别成 Fixed 段，只是文件里 type 字段和当前脚本入参会长期不一致。
    - **worktree 感知**：三个脚本都新增 `git rev-parse --git-dir` 里 `*/worktrees/*` 的检测。`tasks-new.sh` 打警告不阻断（提示多 agent 场景请回主仓库）；`tasks-status.sh` / `tasks-release.sh` 在 worktree 里**自动跳过** `tasks-index.sh`，避免局部视图覆盖 develop 上完整索引。索引由主仓库单点生成——agent 每次 `git pull` develop 之后跑一次即可，或让 SessionEnd hook 自动跑。
  - **v2.2 → v2.3（生命周期语义 + hotfix type + release/dev_verified 字段）**：
    - **status 语义变更（脚本行为不变）**：`done` 从「合 develop」改成「dev 联调通过」；`archived` 从「合 beta 部署 dev 服」改成「已合 main 待打 tag / 部署 prod」。emit_group 段名文案与 Step 3 骨架的更新协议文案同步改了。**存量任务不需要迁移**——status 字段值仍是 doing/todo/done/archived，只是人读的含义变了。**Path C 不自动重写 TASKS.md 顶部的更新协议 prose**（那是手写区），要提示用户是否同步换成新版文案；还要口头告知团队新的分支纪律（dev 是 rolling 沙盒、每个 feat 独立 PR 到 main 发版、hotfix 跳 dev 直切 main）。
    - **hotfix type**：`tasks-new.sh` 支持 `feat|bugfix|chore|hotfix`；`tasks-release.sh` 里 `bugfix|hotfix|fix` 都归 Fixed 段。分支前缀 `hotfix/<slug>`，从 main 直切，跳过 dev 集成。开 hotfix 必须写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」，否则回退到 bugfix。
    - **新增 `release` / `dev_verified` frontmatter 字段**：新登记的任务自带；存量任务缺失时 `get_field` 返回空串，索引脚本静默忽略，**向后兼容——无需批量补齐**。`release: batch-<name>` 在索引行尾贴 `🚂 batch-<name>`，默认 `independent` 不 render。
- **分支模型是参数不是常量**：模板里的 `dev` / `main` 按项目实际分支替换。常见变体：
  - **两段独立发版（默认，v2.3+）**：`dev`（rolling 集成沙盒）+ `main`（prod 发版源）。每个 feature 分支既 merge 到 dev 联调，又独立 PR 到 main 打 tag；dev 不流回 main。
  - **线性三段**（`develop → beta → main`，需独立 staging 环境冒烟）：`done` = 合 develop、`archived` = 合 beta 部署 staging、`release` = 合 main。改 emit_group 段名文案 + Step 3 骨架更新协议为线性描述；hotfix 语义仍成立（跳 develop / beta 直切 main）。
  - **两段无 dev 服**（miniapp 类）：`archived` 段挂「已上传体验版待审核发布」。改 emit_group 段名文案即可。
  - **单段 main**：砍掉「待发布」段和索引脚本里对应的 `emit_group archived` 那行。
- **hotfix 纪律**：`type: hotfix` 是 fast lane，跳过 dev 集成，直接从 main 切分支 → PR 回 main → tag。**开 hotfix 必须在任务描述里写清「命中场景 → 用户影响 → 为什么等不了 dev 集成」**——没这三条一律回退到 bugfix 走 dev 联调。任务描述里没这三条是纪律问题，脚本拦不住。事后要开 `chore/backport-hotfix-<slug>` 把 fix merge 回 dev，避免下次 feature 分支合 dev 时把 hotfix「退回去」。
- **dev 分支纪律**：dev 是 rolling 集成沙盒，允许被 `reset --hard main` 推倒重建。**禁止 dev → main**（会把在途 feature 拖进 prod）；**禁止基于 dev 拉分支**（下一次 reset 会带走）；**禁止 cherry-pick dev 的 commit 回 main**（可能漏依赖）。破这些规矩就回到「dev 里混了半成品没法单独发 prod」的老问题。
- **绝对禁止 `rm`**：删除任何文件时用 `trash`（用户级全局约定）。
