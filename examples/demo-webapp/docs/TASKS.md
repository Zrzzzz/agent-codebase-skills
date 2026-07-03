---
project: acme-shop
updated: 2026-07-03
---

# 进度 · acme-shop

> **更新协议（v2 · 拆文件版）**
> - **每个任务 = `docs/tasks/T-XXX.md`**，本文件的 4 个状态段是它的索引视图，由 `scripts/tasks-index.sh` 生成。
> - 新增任务：跑 `bash scripts/tasks-new.sh <feat|fix> <slug> "<一句话标题>"` → 得到 `docs/tasks/T-XXX.md`，填 `agent`、`files` 等字段。**不要手写 T-XXX 编号**，脚本用 mkdir 锁原子分配，防止多 agent 撞号。
> - 状态流转 = 改任务文件的 `status` 字段 + 更新 `updated` + 跑 `bash scripts/tasks-index.sh`：
>   1. `status: doing` — 开始动手，在 frontmatter 标 `@agent-id` 认领；
>   2. feat/bugfix 合回 `develop` → `status: done`，标日期；
>   3. 合 `beta` 部署 dev 服 → `status: archived`，标部署日期；
>   4. 合 `main` 上线 prod → 把该任务提炼成 Keep a Changelog 条目写入 `CHANGELOG.md` 新版本段，然后 `trash docs/tasks/T-XXX.md`，跑索引脚本刷新。
> - 挑任务时优先选影响文件不重叠的，减少并行冲突。
> - 决策 / 踩坑不进任务文件，写到本文件底部「🧭 约束与决策」「⚠️ 踩坑与教训」（这两段是本文件手写区，索引脚本不会动）。

<!-- BEGIN:TASKS-INDEX (auto — do not edit; run scripts/tasks-index.sh) -->

## 🔨 进行中

- [ ] **T-002** · [frontend] 结算页接入优惠券选择与抵扣展示 · `@claude-a` · `feat/coupon-checkout` · 影响文件: frontend/src/pages/checkout/**, frontend/src/api/client.ts · [详情](tasks/T-002.md)

## 📋 待办（优先级从上到下）

- [ ] **T-003** · [backend] 修复库存超卖：下单扣减未加行锁 · `bugfix/oversell-lock` · 影响文件: backend/api/orders.py, backend/models/inventory.py · [详情](tasks/T-003.md)

## ✅ 已完成（develop 已合入，待发 dev 服）

- [x] **T-001** · [frontend] 商品列表首屏加载优化（LCP 3.4s → 1.6s） · `@claude-b` · `feat/plp-perf` · 影响文件: frontend/src/pages/plp/** · 2026-07-01 · [详情](tasks/T-001.md)

## 🗄️ 历史归档（已部署 dev 服，待上线 prod）

_（暂无。）_

<!-- END:TASKS-INDEX -->

---

## 🧭 约束与决策（只增不删）

- **D-1** (2026-06-28)：优惠券金额校验只在后端做，前端仅展示 — 原因：防止金额被前端篡改。
- **D-2** (2026-07-01)：性能优化必须记录 baseline 前后数字到 session-notes — 原因：无对照数字的优化无法回归验证。

## ⚠️ 踩坑与教训

- pnpm v8 锁文件在 v9 workspace 下解析失败 → 根因：workspace 协议格式变更 → 结论：全员统一 pnpm ≥ 9，CI 加版本检查。
- dev 服 `/api` 请求 10s 后被掐 → 根因：nginx 默认 proxy_read_timeout → 结论：长任务接口一律走异步任务队列，不改 nginx。
