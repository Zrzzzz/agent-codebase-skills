---
id: T-oversell-lock
title: "[backend] 修复库存超卖：下单扣减未加行锁"
status: todo
type: bugfix
priority: 1
agent: ""
branch: bugfix/oversell-lock
release: independent
dev_verified: ""
created: 2026-07-03
files: backend/api/orders.py, backend/models/inventory.py
---

## 描述

大促压测中同一 SKU 并发下单出现负库存。命中场景：两个请求同时读到库存 1 → 各自扣减 → -1。根因：扣减走「读-改-写」，无行锁也无原子更新。

## 子任务

- [ ] 扣减改为 `UPDATE ... SET stock = stock - 1 WHERE id = ? AND stock >= 1` 原子语句
- [ ] 扣减失败返回 409，前端提示「已售罄」
- [ ] 补并发回归测试（pytest + asyncio，100 并发扣 10 库存）

## 备注

不引入分布式锁——单库场景原子 UPDATE 足够；分库后再议（记入 TASKS.md 决策区）。
