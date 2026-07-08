---
project: acme-shop
updated: 2026-07-03
---

# 进度 · acme-shop

> **更新协议（v3 · 无编号 + hook 自动化）**
> - **每个任务 = `docs/tasks/T-<slug>.md`**，文件名即 ID——无编号无锁，任何 worktree 里直接建。本文件 4 个状态段是索引视图，由 git hook（pre-commit / post-merge）自动重生成，一般无需手工跑 `scripts/tasks-index.sh`。
> - **入口协议**：用户报告的 bug / 提出的需求，先登记任务 + 切 `<type>/<slug>` 分支，再动代码（详见 AGENTS.md「任务入口协议」；pre-commit hook 会校验）。登记：`bash scripts/tasks-new.sh <feat|bugfix|chore|hotfix> <slug> "<标题>" [priority]`，或直接按 `docs/tasks/` 现有文件的模板 Write。
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

- [ ] **T-coupon-checkout** · [frontend] 结算页接入优惠券选择与抵扣展示 · `@claude-a` · `feat/coupon-checkout` · 影响文件: frontend/src/pages/checkout/**, frontend/src/api/client.ts · [详情](tasks/T-coupon-checkout.md)

## 📋 待办（priority 升序）

- [ ] **T-oversell-lock** · [backend] 修复库存超卖：下单扣减未加行锁 · P1 · `bugfix/oversell-lock` · 影响文件: backend/api/orders.py, backend/models/inventory.py · [详情](tasks/T-oversell-lock.md)

## ✅ 已完成（dev 联调通过，待合 main 独立发版）

- [x] **T-plp-perf** · [frontend] 商品列表首屏加载优化（LCP 3.4s → 1.6s） · `@claude-b` · `feat/plp-perf` · 影响文件: frontend/src/pages/plp/** · 2026-07-01 · [详情](tasks/T-plp-perf.md)

## 🗄️ 待发布（已合 main，待打 tag / 部署 prod）

_（暂无。）_

<!-- END:TASKS-INDEX -->

---

## 🧭 约束与决策（只增不删）

- **D-1** (2026-06-28)：优惠券金额校验只在后端做，前端仅展示 — 原因：防止金额被前端篡改。
- **D-2** (2026-07-01)：性能优化必须记录 baseline 前后数字到 session-notes — 原因：无对照数字的优化无法回归验证。

## ⚠️ 踩坑与教训

- pnpm v8 锁文件在 v9 workspace 下解析失败 → 根因：workspace 协议格式变更 → 结论：全员统一 pnpm ≥ 9，CI 加版本检查。
- dev 服 `/api` 请求 10s 后被掐 → 根因：nginx 默认 proxy_read_timeout → 结论：长任务接口一律走异步任务队列，不改 nginx。
