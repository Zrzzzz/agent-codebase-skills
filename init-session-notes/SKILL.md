---
name: init-session-notes
version: 2.0.0
description: |
  为项目初始化「会话归档」自动化基础设施：
  1. SessionEnd hook：每次会话结束自动用 claude -p 提炼对话要点追加到 docs/session-notes.md，
     含超阈值自动压缩（默认 45KB）。
  2. docs/session-notes.md：长期决策与踩坑沉淀（hook 维护，模板由本 skill 初始化）。
  本 skill 只管「会话归档」：不写 CLAUDE.md / AGENTS.md 分层约定——那些归
  [`init-agents-md`](../init-agents-md/SKILL.md)；不初始化 docs/TASKS.md 任务管理——
  那些归 [`init-agent-task-md`](../init-agent-task-md/SKILL.md)。
  使用：/init-session-notes；或当用户说「给项目装会话归档」「我想要自动整理对话要点」时也命中本 skill。
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - AskUserQuestion
---

# Init Session Notes（会话归档初始化）

为项目装一套**会话结束时自动归档**的基础设施：SessionEnd hook 启动一个完全脱离的守护进程，用 `claude -p` 把这次对话提炼成几条要点追加进 `docs/session-notes.md`。

> ⚠️ 该 skill 只装 hook 和初始化 session-notes。CLAUDE.md / AGENTS.md 的分层约定归 [`init-agents-md`](../init-agents-md/SKILL.md)；docs/TASKS.md 任务管理（含任务推进自动检测）归 [`init-agent-task-md`](../init-agent-task-md/SKILL.md)。三者**完全独立**，可单装；想要全套就各跑一次。

---

## Step 0：探测项目状态

```bash
git rev-parse --git-dir 2>/dev/null >/dev/null && echo "git=yes" || echo "git=no"
[ -f .claude/hooks/summarize-session.sh ] && echo "hook=exists" || echo "hook=new"
[ -f .claude/hooks/_summarize-worker.sh ] && echo "worker=exists" || echo "worker=new"
[ -f .claude/settings.local.json ] && echo "settings=exists" || echo "settings=new"
[ -f docs/session-notes.md ] && echo "notes=exists" || echo "notes=new"
```

对已存在的脚本 / settings：用 `AskUserQuestion` 询问是否覆盖；对已存在的 session-notes：默认**不动**（避免覆盖用户历史沉淀），只在文件不存在时初始化。

---

## Step 1：创建目录结构

```bash
mkdir -p .claude/hooks
mkdir -p docs
```

---

## Step 2：写入 summarize-session.sh

将以下内容**原样**写入 `.claude/hooks/summarize-session.sh`，然后 `chmod +x` 它：

```bash
#!/usr/bin/env bash
# SessionEnd hook：会话结束时提炼本次对话要点，追加到 docs/session-notes.md。
#
# 立即返回：把耗时工作交给完全脱离的守护进程，绝不阻塞退出/clear。
# 真正脱离：perl double-fork + setsid()，worker 进入新会话/新进程组。
# 防递归：worker 内 spawn 的 claude -p 用 env 守卫 + --settings disableAllHooks。
set -u

[ -n "${CLAUDE_SESSION_SUMMARY_RUNNING:-}" ] && exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
worker="$here/_summarize-worker.sh"

input="$(cat)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$(pwd)"

[ -z "$transcript" ] && exit 0
[ ! -f "$transcript" ] && exit 0

perl -e '
  use POSIX qw(setsid);
  $SIG{HUP} = "IGNORE";
  exit 0 if fork;
  setsid();
  exit 0 if fork;
  open(STDIN,  "<", "/dev/null");
  open(STDOUT, ">", "/dev/null");
  open(STDERR, ">", "/dev/null");
  exec @ARGV;
' bash "$worker" "$transcript" "$cwd" </dev/null >/dev/null 2>&1 &

exit 0
```

---

## Step 3：写入 _summarize-worker.sh

将以下内容**原样**写入 `.claude/hooks/_summarize-worker.sh`，然后 `chmod +x`：

```bash
#!/usr/bin/env bash
# 由 summarize-session.sh 以「完全脱离的守护进程」方式调起。
# 参数：$1 = transcript_path（JSONL），$2 = 项目 cwd
# 职责：抽取对话文本 → 无头 claude -p 提炼 → 追加到 docs/session-notes.md
# （任务推进自动检测段由 init-agent-task-md skill 按需追加在本文件末尾）
set -u

transcript="${1:-}"
cwd="${2:-}"
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0
[ -z "$cwd" ] && cwd="$(pwd)"

notes_dir="$cwd/docs"
notes="$notes_dir/session-notes.md"
log="$cwd/.claude/hooks/summarize-session.log"

compress_threshold="${SESSION_NOTES_COMPRESS_BYTES:-45000}"

# ── 抽取对话文本 ──────────────────────────────────────────────────
convo="$(jq -r '
    select(.type=="user" or .type=="assistant")
    | (.message.role // .type) as $r
    | (.message.content
       | if type=="string" then .
         elif type=="array" then [.[] | (.text // empty)] | join("\n")
         else "" end) as $t
    | select(($t|type=="string") and ($t|length) > 0)
    | "[\($r)] \($t)"
  ' "$transcript" 2>/dev/null | tail -c 60000)"
[ -z "$convo" ] && exit 0

# ── session-notes 提炼 ────────────────────────────────────────────
prompt="下面是一次 Claude Code 对话记录。请用简体中文提炼出对【今后本项目开发】有长期参考价值的内容：关键决策、新约定、踩过的坑及解决办法、重要命令或路径。只输出 3-8 条 markdown 无序列表，每条一句话。若本次对话没有值得长期保留的内容，只输出一行 NONE。

对话记录：
$convo"

summary="$(CLAUDE_SESSION_SUMMARY_RUNNING=1 claude -p "$prompt" --settings '{"disableAllHooks":true}' 2>>"$log")"
[ -z "$summary" ] && exit 0
[ "$(printf '%s' "$summary" | tr -d '[:space:]')" = "NONE" ] && exit 0

mkdir -p "$notes_dir"

# ── 超阈值时先压缩去重 ────────────────────────────────────────────
if [ -f "$notes" ]; then
  size="$(wc -c <"$notes" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$size" ] && [ "$size" -gt "$compress_threshold" ]; then
    old="$(cat "$notes")"
    cprompt="下面是本项目开发笔记 session-notes.md 的全文，已变得冗长且有重复。请压缩：按主题去重归并，保留每一条唯一事实（架构决策、契约、踩坑及解决办法、commit 哈希、命令、路径、baseline 数字），删除重复表述与已被后续实现取代的纯讨论。保持顶部 \`# Session Notes\` 标题与引用说明（> 开头的行）原样。直接输出压缩后的完整 markdown 文件内容，不要任何解释、前后缀或代码围栏。

session-notes.md 全文：
$old"
    compressed="$(CLAUDE_SESSION_SUMMARY_RUNNING=1 claude -p "$cprompt" --settings '{"disableAllHooks":true}' 2>>"$log")"
    clen="$(printf '%s' "$compressed" | wc -c | tr -d '[:space:]')"
    if [ -n "$compressed" ] \
       && [ "$clen" -lt "$size" ] \
       && [ "$clen" -gt 800 ] \
       && printf '%s' "$compressed" | head -n 5 | grep -q '# Session Notes'; then
      cp "$notes" "$notes.bak"
      printf '%s\n' "$compressed" > "$notes"
    else
      printf '[%s] compress skipped (clen=%s size=%s)\n' "$(date '+%F %T')" "${clen:-0}" "$size" >> "$log"
    fi
  fi
fi

# ── 追加本次 session 提炼 ──────────────────────────────────────────
{
  printf '\n## %s\n\n' "$(date '+%Y-%m-%d %H:%M')"
  printf '%s\n' "$summary"
} >> "$notes"
```

---

## Step 4：配置 settings.local.json

读取当前目录的 `.claude/settings.local.json`（不存在则视为 `{}`），合并 SessionEnd hook 后写回。`<CWD>` 用当前工作目录的**绝对路径**替换：

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash <CWD>/.claude/hooks/summarize-session.sh",
            "timeout": 15,
            "statusMessage": "正在归档本次对话要点到 docs/session-notes.md…"
          }
        ]
      }
    ]
  }
}
```

若已存在 `hooks.SessionEnd`，用 `AskUserQuestion` 询问是否覆盖。

---

## Step 5：初始化 docs/session-notes.md

**session-notes.md**（仅在文件不存在时写入；第一行 `# Session Notes` 是 worker 压缩校验依据，必须保留）：

```markdown
# Session Notes（自动生成）

> 本文件由 `.claude/hooks/summarize-session.sh`（SessionEnd hook）在每次会话结束时自动追加。
> 内容是对话要点的 LLM 提炼，供今后开发参考；可随时手工编辑/裁剪。

---
```

---

## Step 6：输出初始化报告

向用户输出：

```
✅ 会话归档已初始化：

  hook：
    • .claude/hooks/summarize-session.sh         （[新建/已覆盖/跳过]）
    • .claude/hooks/_summarize-worker.sh         （[新建/已覆盖/跳过]）
    • .claude/settings.local.json                （SessionEnd hook [已注册/已存在]）
  状态文件：
    • docs/session-notes.md                      （[新建/已存在保留]）

会话结束时（quit / Ctrl-D / clear）hook 会自动跑：
  1. 抽 transcript → claude -p 提炼 3-8 条要点 → 追加到 docs/session-notes.md
  2. session-notes 超过 45KB 时先 LLM 压缩去重

下一步建议：
  1. 若想要任务管理层（docs/TASKS.md + 任务推进自动检测），运行 `/init-agent-task-md`
  2. 若想要分层 memory 约定（CLAUDE.md / AGENTS.md + 模块嵌套），运行 `/init-agents-md`
  3. 跑一次正常对话后退出，验证 docs/session-notes.md 被自动追加
```

---

## 注意事项

- **hook 脚本不要改**：Step 2/3 的两段 bash 经过实战打磨（perl double-fork、env 防递归、压缩阈值 45KB），改动需谨慎；特别**不要去掉** `--settings '{"disableAllHooks":true}'` 与 `CLAUDE_SESSION_SUMMARY_RUNNING=1` 双保险，否则会无限递归触发。
- **绝对路径**：settings.local.json 里的 hook 命令必须用**绝对路径**（用当前 `pwd` 替换 `<CWD>`），否则换工作目录后 hook 会找不到脚本。
- **session-notes 已存在时不动**：用户的历史沉淀珍贵，本 skill 只在文件不存在时初始化模板；要重置请用户自己改名/`trash` 后重跑。
- **任务推进自动检测不在本 skill**：由 [`init-agent-task-md`](../init-agent-task-md/SKILL.md) 在 `_summarize-worker.sh` 末尾**追加**检测段（本 skill 重装覆盖 worker 后需重跑该 skill 补回）。
- **依赖 `jq` + `perl` + `claude` CLI**：mac/linux 自带 perl；jq 多数项目环境已有；`claude` CLI 由 Claude Code 本体提供。运行前可 `command -v jq perl claude` 验证。
- **绝对禁止 `rm`**：删除任何文件时用 `trash`（用户级全局约定）。
